// The Linux side of live directory grants: mount propagation between the
// broker's namespace and the running sandbox.
//
// Seatbelt hands out a capability -- the broker issues a read-write extension
// token outside the sandbox and the launcher consumes it, widening a sandbox
// that is already running. Linux has no such token, and bubblewrap's mounts
// are fixed the moment it execs. What Linux does have is mount propagation,
// which gives the same shape:
//
//   * The broker unshares a user + mount namespace, so it can bind-mount
//     without being root on the machine. Nothing it mounts is visible to the
//     host, and it all disappears when the broker exits.
//   * One directory in that namespace -- the grant carrier -- is marked
//     MS_SHARED before the session starts. bwrap marks everything it inherits
//     a slave and then binds the carrier into the sandbox, so the sandbox's
//     copy stays in the broker's peer group: a bind the broker adds under the
//     carrier appears inside the running sandbox immediately.
//   * The "token" is therefore the carrier path. The launcher, which holds
//     CAP_SYS_ADMIN over its own mount namespace (a nested user namespace it
//     creates before forking the harness), binds that path onto the real one,
//     and umounts it to revoke.
//
// The carrier only ever holds directories that have already been granted, so
// the second path they are visible at inside the sandbox gives away nothing.
// What is NOT in the sandbox at any point is a view of the whole filesystem:
// the broker keeps that on its side of the boundary, exactly as the token
// issuer does on macOS.

use crate::ffi;
use crate::profile::GRANT_ROOT;
use std::ffi::CString;
use std::io::Error as IoError;
use std::os::raw::{c_ulong, c_void};
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

enum Role {
    // Outside the sandbox, holding the grant carrier. None when this machine
    // would not let us have a mount namespace, which costs live grants but not
    // the session.
    Host(Option<PathBuf>),
    // Inside the sandbox, able to mount or not for the same reason.
    Guest { mounting: bool },
}

pub struct Sandbox {
    role: Role,
}

impl Sandbox {
    pub fn host() -> Result<Self, String> {
        let carrier = match enter_namespaces() {
            Ok(()) => match open_carrier() {
                Ok(dir) => Some(dir),
                Err(e) => {
                    eprintln!("aibox: no grant carrier ({e}); allow takes effect next session");
                    None
                }
            },
            Err(e) => {
                eprintln!("aibox: {e}; allow takes effect next session");
                None
            }
        };
        Ok(Sandbox {
            role: Role::Host(carrier),
        })
    }

    // Inside the sandbox, a nested user namespace is what makes the launcher
    // able to mount at all: bubblewrap leaves it with no capabilities, and an
    // unprivileged process is always permitted to become root of a namespace
    // of its own. The harness is forked after this and inherits the mount
    // namespace, so later binds reach it; it execs, so it keeps none of the
    // capabilities.
    pub fn guest() -> Result<Self, String> {
        // A session that cannot take grants is still a working session, so a
        // machine with user namespaces switched off gets the sandbox and an
        // honest error on `allow` rather than nothing at all.
        let mounting = match enter_namespaces() {
            Ok(()) => true,
            Err(e) => {
                eprintln!("aibox: {e}; this session cannot take live grants");
                false
            }
        };
        Ok(Sandbox {
            role: Role::Guest { mounting },
        })
    }

    pub fn session_command(
        &self,
        plan: &Path,
        launcher: &Path,
        harness: &[String],
    ) -> Result<Command, String> {
        let text = std::fs::read_to_string(plan)
            .map_err(|e| format!("read plan {}: {e}", plan.display()))?;
        let bwrap = which_bwrap()?;
        let mut c = Command::new(bwrap);
        c.args(crate::profile::parse(&text));
        if let Role::Host(Some(carrier)) = &self.role {
            c.arg("--ro-bind").arg(carrier).arg(GRANT_ROOT);
        }
        c.arg("--")
            .arg(launcher)
            .arg("launch")
            .arg("--")
            .args(harness);
        Ok(c)
    }

    // Binds the directory into the carrier, where the sandbox picks it up by
    // propagation. Returns the path the launcher must bind onto the real one.
    pub fn issue(&self, path: &str) -> Result<String, String> {
        let Role::Host(carrier) = &self.role else {
            return Err("not the granting side".to_string());
        };
        let carrier = carrier
            .as_ref()
            .ok_or("this session has no grant carrier; restart it to pick up the manifest")?;
        guard_state_root(path)?;
        guard_sensitive(path)?;
        let slot = carrier.join(slug(path));
        std::fs::create_dir_all(&slot).map_err(|e| format!("create {}: {e}", slot.display()))?;
        bind(Path::new(path), &slot)?;
        Ok(format!("{GRANT_ROOT}/{}", slug(path)))
    }

    // Drops the broker's own copy once the launcher has let go of its bind.
    pub fn revoke(&self, path: &str) {
        let Role::Host(Some(carrier)) = &self.role else {
            return;
        };
        let slot = carrier.join(slug(path));
        detach(&slot);
        let _ = std::fs::remove_dir(&slot);
    }

    // Binds the carrier path onto the real one, which is what the harness
    // reaches for. The directory identifies the mount, so the handle carries
    // the one other thing release needs: whether the mount point was ours.
    pub fn consume(&self, token: &str, dir: &str) -> Result<i64, String> {
        if !matches!(self.role, Role::Guest { mounting: true }) {
            return Err("this session cannot mount".to_string());
        }
        if !Path::new(token).starts_with(GRANT_ROOT) {
            return Err(format!("grant outside {GRANT_ROOT}"));
        }
        let target = Path::new(dir);
        let created = !target.exists();
        if created {
            // The parent is usually a directory bwrap created in the sandbox's
            // own tmpfs, so this succeeds; a grant under a read-only mount is
            // the case that does not, and it reports why.
            std::fs::create_dir_all(target)
                .map_err(|e| format!("create mountpoint {dir}: {e}"))?;
        }
        bind(Path::new(token), target)?;
        Ok(i64::from(created))
    }

    // Unmounting alone would leave the empty mount point behind, and writes to
    // a revoked directory would then quietly succeed against the sandbox's own
    // tmpfs instead of failing. So a mount point this created is removed with
    // it -- and only one this created: the same directory could be a real one
    // inside an already-granted tree.
    pub fn release(&self, handle: i64, dir: &str) {
        detach(Path::new(dir));
        if handle == 1 {
            let _ = std::fs::remove_dir(dir);
        }
    }
}

impl Drop for Sandbox {
    fn drop(&mut self) {
        // The mounts die with the namespace; the directories behind them are
        // real, and would otherwise pile up beside the socket.
        if let Role::Host(Some(carrier)) = &self.role {
            if let Ok(entries) = std::fs::read_dir(carrier) {
                for slot in entries.flatten() {
                    detach(&slot.path());
                    let _ = std::fs::remove_dir(slot.path());
                }
            }
            detach(carrier);
            let _ = std::fs::remove_dir(carrier);
        }
    }
}

// A user namespace is what makes an ordinary user able to mount at all: the
// process becomes root of a namespace of its own, and its mount namespace is
// owned by that. The identity uid/gid map keeps every file the process
// touches owned by the same user it was before.
fn enter_namespaces() -> Result<(), String> {
    let (uid, gid) = unsafe { (ffi::getuid(), ffi::getgid()) };
    if unsafe { ffi::unshare(ffi::CLONE_NEWUSER | ffi::CLONE_NEWNS) } != 0 {
        return Err(format!(
            "cannot create a user namespace ({}); unprivileged user namespaces must be enabled",
            IoError::last_os_error()
        ));
    }
    // Denying setgroups is a precondition for writing gid_map unprivileged.
    let _ = std::fs::write("/proc/self/setgroups", "deny");
    std::fs::write("/proc/self/uid_map", format!("{uid} {uid} 1"))
        .map_err(|e| format!("write uid_map: {e}"))?;
    std::fs::write("/proc/self/gid_map", format!("{gid} {gid} 1"))
        .map_err(|e| format!("write gid_map: {e}"))?;
    // Receive mounts from the rest of the machine, propagate none back to it.
    mount(None, Path::new("/"), ffi::MS_REC | ffi::MS_SLAVE)
        .map_err(|e| format!("make / rslave: {e}"))
}

// The grant carrier: a directory in the broker's namespace, mounted on itself
// so it can carry a propagation peer group of its own. Everything the broker
// binds beneath it reaches the sandbox that has it bound.
//
// Where it sits matters. The sandbox reaches it only through the one bind the
// broker adds, so it must not ALSO be reachable by path: the harness could
// otherwise pre-create a slot -- the name is a hash of a path it can compute --
// underneath the broker. Both candidates below are invisible from inside: the
// runtime directory is replaced by the sandbox's own tmpfs, and the state root
// is never mounted.
fn open_carrier() -> Result<PathBuf, String> {
    let base = match std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from) {
        Some(run) if run.is_absolute() => run,
        _ => state_root(),
    };
    let dir = base.join(format!("aibox-grants-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).map_err(|e| format!("create {}: {e}", dir.display()))?;
    std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o700))
        .map_err(|e| format!("secure {}: {e}", dir.display()))?;
    bind(&dir, &dir)?;
    mount(None, &dir, ffi::MS_SHARED).map_err(|e| format!("share {}: {e}", dir.display()))?;
    Ok(dir)
}

// A grant that reached the state root would hand the sandbox the capability
// the broker authenticates with. The Seatbelt profile denies that path even
// against a dynamic grant; here the grant itself is refused.
// On macOS the profile's hard-deny outranks any consumed extension, so a grant
// simply cannot re-open a crown-jewel secret. A mount namespace has no rule
// that denies a path back out of a mount -- a bind is a bind -- so the same
// guarantee has to live in the granting path instead. Granting a parent of a
// secret is refused too: the bind would carry it in whole.
fn guard_sensitive(path: &str) -> Result<(), String> {
    let Some(home) = std::env::var_os("HOME") else {
        return Ok(());
    };
    let home = Path::new(&home);
    let path = Path::new(path);
    for rel in crate::profile::SENSITIVE_HOME {
        let secret = home.join(rel);
        if secret.starts_with(path) || path.starts_with(&secret) {
            return Err(format!(
                "refusing to grant {}: it reaches {}",
                path.display(),
                secret.display()
            ));
        }
    }
    Ok(())
}

fn guard_state_root(path: &str) -> Result<(), String> {
    let state = state_root();
    let path = Path::new(path);
    if state.starts_with(path) || path.starts_with(&state) {
        return Err(format!("refusing to grant {}: aibox state", path.display()));
    }
    Ok(())
}

// Resolved here rather than left to exec so the first run on a machine without
// bubblewrap says what is missing.
fn which_bwrap() -> Result<PathBuf, String> {
    if let Some(explicit) = std::env::var_os("AIBOX_BWRAP") {
        return Ok(PathBuf::from(explicit));
    }
    let path = std::env::var_os("PATH").unwrap_or_default();
    std::env::split_paths(&path)
        .map(|dir| dir.join("bwrap"))
        .find(|p| p.is_file())
        .ok_or_else(|| "bwrap is not on PATH; install bubblewrap".to_string())
}

fn state_root() -> PathBuf {
    match std::env::var("AIBOX_STATE_ROOT") {
        Ok(s) if !s.is_empty() => PathBuf::from(s),
        _ => Path::new(&std::env::var("HOME").unwrap_or_default()).join(".aibox/state"),
    }
}

fn bind(src: &Path, dest: &Path) -> Result<(), String> {
    mount(Some(src), dest, ffi::MS_BIND | ffi::MS_REC)
        .map_err(|e| format!("bind {} at {}: {e}", src.display(), dest.display()))
}

// Lazy, so a directory the harness is sitting in still stops resolving now.
fn detach(path: &Path) {
    if let Ok(p) = CString::new(path.as_os_str().as_bytes()) {
        unsafe {
            ffi::umount2(p.as_ptr(), ffi::MNT_DETACH);
        }
    }
}

fn mount(src: Option<&Path>, dest: &Path, flags: c_ulong) -> Result<(), IoError> {
    let s = src
        .map(|p| CString::new(p.as_os_str().as_bytes()))
        .transpose()
        .map_err(|_| IoError::from(std::io::ErrorKind::InvalidInput))?;
    let d = CString::new(dest.as_os_str().as_bytes())
        .map_err(|_| IoError::from(std::io::ErrorKind::InvalidInput))?;
    let src_ptr = s.as_ref().map_or(std::ptr::null(), |c| c.as_ptr());
    let rc = unsafe {
        ffi::mount(
            src_ptr,
            d.as_ptr(),
            std::ptr::null(),
            flags,
            std::ptr::null::<c_void>(),
        )
    };
    if rc == 0 {
        Ok(())
    } else {
        Err(IoError::last_os_error())
    }
}

// Names a carrier slot after the path it carries: stable across sessions,
// free of the path's own separators and spaces, and short enough that a deep
// grant does not run the mount point past PATH_MAX. FNV-1a is enough: the
// name is an index into the carrier, not a secret, and the broker binds the
// real path either way.
fn slug(path: &str) -> String {
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for b in path.as_bytes() {
        h ^= u64::from(*b);
        h = h.wrapping_mul(0x0000_0100_0000_01b3);
    }
    format!("{h:016x}")
}

#[cfg(test)]
mod tests {
    use super::{guard_sensitive, guard_state_root, slug};

    #[test]
    fn slugs_are_stable_and_path_safe() {
        assert_eq!(slug("/home/eric/x"), slug("/home/eric/x"));
        assert_ne!(slug("/home/eric/x"), slug("/home/eric/y"));
        assert!(slug("/a b/c").chars().all(|c| c.is_ascii_hexdigit()));
    }

    #[test]
    fn refuses_grants_that_would_reach_aibox_state() {
        std::env::set_var("AIBOX_STATE_ROOT", "/home/eric/.aibox/state");
        assert!(guard_state_root("/home/eric/.aibox/state").is_err());
        assert!(guard_state_root("/home/eric/.aibox/state/x").is_err());
        // An ancestor would carry it in just as surely.
        assert!(guard_state_root("/home/eric").is_err());
        assert!(guard_state_root("/home/eric/Code").is_ok());
        std::env::remove_var("AIBOX_STATE_ROOT");
    }

    // Seatbelt denies these back out of any grant; here nothing can, so the
    // refusal is the guarantee.
    #[test]
    fn refuses_grants_that_would_reach_a_protected_secret() {
        std::env::set_var("HOME", "/home/eric");
        assert!(guard_sensitive("/home/eric/.ssh").is_err());
        assert!(guard_sensitive("/home/eric/.ssh/keys").is_err());
        // An ancestor would carry it in whole.
        assert!(guard_sensitive("/home/eric").is_err());
        assert!(guard_sensitive("/home/eric/.config").is_err());
        // The agent socket is not a secret directory: granting it is exactly
        // what `aibox allow` is for.
        assert!(guard_sensitive("/tmp/ssh-XXXX").is_ok());
        assert!(guard_sensitive("/home/eric/Code").is_ok());
    }
}
