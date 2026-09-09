// Generates the bubblewrap argument plan for a workspace -- the Linux
// counterpart of the Seatbelt profile.
//
// Seatbelt is a deny-by-default *policy* over the real filesystem; bubblewrap
// is a deny-by-default *view* of it. Nothing is reachable inside the sandbox
// unless it is mounted, so where the profile spells out an allow-list of
// subpaths, this spells out the same list as binds. The two tables are kept
// separate rather than shared because the paths themselves differ (there is no
// ~/Library on Linux, no /nix/store on stock macOS) and because the mechanisms
// diverge in three places worth naming:
//
//   * A secret that sits INSIDE an allowed tree cannot simply be left out, so
//     it is masked: /dev/null over a file, an empty tmpfs over a directory.
//   * $HOME itself is a persistent directory of aibox's own (~/.aibox/home),
//     not the real home. Tools write to $HOME constantly, and more importantly
//     they write ATOMICALLY: claude persists ~/.claude.json by renaming a
//     sibling over it, and rename(2) onto a bind-mounted file fails with
//     EBUSY. A real directory underneath makes those writes work while keeping
//     them out of the real home; everything meant to be shared is mounted onto
//     it from the real one.
//   * The plan is emitted as one argument per line, so the broker can hand it
//     to bwrap verbatim after appending the session's own grant carrier.
//
// Dynamic directories never appear here -- they arrive at runtime as binds
// propagated from the broker's mount namespace (see bwrap.rs).

use crate::repo;
use std::path::{Path, PathBuf};

// Read-only home files the toolchain needs. ~/.rustup is deliberately not here
// but read-write below: rustup installs a toolchain into it whenever a repo's
// rust-toolchain.toml names one it does not have. The shell startup files are
// load-bearing for every `sh -c` the harness runs: bash sources .bashrc in
// subshells, so without them each one trips over a missing file before it does
// any work. .nix-profile is where a Nix user's PATH actually points.
const RO_HOME: &[&str] = &[
    ".gitconfig",
    ".config/git",
    ".config/delta",
    ".terminfo",
    ".bashrc",
    ".bash_profile",
    ".profile",
    ".zshenv",
    ".zshrc",
    ".zprofile",
    ".inputrc",
    ".nix-profile",
    ".nix-defexpr",
    ".local/state/nix/profiles",
    ".orca/agent-hooks",
];

// Config/cred/cache locations that must persist, relative to $HOME. These are
// bound from the REAL home over the overlay, so the harness shares them with
// the host exactly as the Seatbelt profile does.
const RW_HOME: &[&str] = &[
    // Agents and aibox itself.
    ".claude",
    ".pi",
    ".codex",
    ".config/opencode",
    ".local/share/opencode",
    ".config/fish",
    ".local/share/fish",
    ".clipboard-images",
    ".aibox/activity",
    // Orca's hook channel, and only that: the endpoint file the hooks read and
    // the spool they fall back to. Its userData directory (~/.config/orca on
    // this platform) is deliberately not mounted -- it holds the app's cookies,
    // vault and account credentials.
    ".config/orca/agent-hooks",
    // JVM: the kotlin daemon, sdkman-managed JDKs, and where java.util.prefs
    // lands.
    ".local/share/kotlin",
    ".java",
    ".sdkman",
    ".konan",
    ".skiko",
    // Android. ~/.android holds the AVDs, the emulator state and the adb key
    // that authorizes a device; without it adb re-prompts on every device.
    "Android/Sdk",
    // Swift.
    ".swiftpm",
    // Python: interpreters and the --user prefix.
    ".pyenv",
    ".conda",
    ".ipython",
    ".jupyter",
    ".config/pip",
    ".config/pypoetry",
    ".local/lib",
    // Node: the package managers and their version managers.
    ".nvm",
    ".fnm",
    ".volta",
    ".bun",
    ".deno",
    ".yarn",
    ".config/yarn",
    ".corepack",
    ".node-gyp",
    ".pnpm-store",
    // Go.
    "go",
    ".cache/go-build",
    // Ruby, which mobile work reaches through fastlane.
    ".gem",
    ".bundle",
];

// Toolchain caches and local app data that need persistent write access,
// created when absent: cargo writes its registry cache to ~/.cargo on the
// first fetch and npm creates ~/.npm lazily, and a bind needs its source to
// exist. The credential files inside both are masked below.
const RW_HOME_ALWAYS: &[&str] = &[
    ".cargo",
    ".rustup",
    ".npm",
    ".cache/nix",
    ".local/share/rtk",
    ".gradle",
    ".m2",
    ".android",
    ".cache/uv",
    ".local/share/uv",
    ".cache/pip",
    ".cache/pypoetry",
    ".cache/node-gyp",
    ".cache/yarn",
    ".cache/pnpm",
    ".local/share/pnpm",
    ".cache/ms-playwright",
    ".cache/org.swift.swiftpm",
    ".cache/sccache",
    ".cache/ccache",
    ".local/bin",
];

// Crown-jewel secrets. Most need no rule at all -- an unmounted path is not
// in the sandbox -- but these sit INSIDE a tree granted above, so a mask is
// stacked on top: an empty tmpfs for a directory, /dev/null for a file. Only
// the ones that exist are emitted, because bwrap would otherwise CREATE the
// destination in the real directory the mount came from.
pub const SENSITIVE_HOME: &[&str] = &[
    ".ssh",
    ".gnupg",
    ".aws",
    ".kube",
    ".docker",
    ".config/gh",
    ".config/gcloud",
    ".netrc",
    ".git-credentials",
    ".npmrc",
    ".pypirc",
    ".config/op",
    ".config/containers",
    ".local/share/keyrings",
    ".gradle/gradle.properties",
    ".m2/settings.xml",
    ".m2/settings-security.xml",
    ".cargo/credentials",
    ".cargo/credentials.toml",
    ".rustup/credentials",
    ".rustup/credentials.toml",
    ".rustup/secrets",
    ".rustup/secrets.toml",
    ".gem/credentials",
    ".bundle/config",
    ".config/pypoetry/auth.toml",
];

// System + toolchain, read-only. On NixOS every PATH binary resolves into the
// immutable /nix/store through /run/current-system, so read access there is
// safe and load-bearing. /sys is read by runtimes sizing themselves against
// cgroup limits.
const RO_ABSOLUTE: &[&str] = &[
    "/bin",
    "/etc",
    "/lib",
    "/lib32",
    "/lib64",
    "/nix",
    "/opt",
    "/sbin",
    "/sys",
    "/usr",
    "/var/empty",
    "/run/current-system",
    // getaddrinfo goes through these when the host runs systemd-resolved or
    // nscd; /etc/resolv.conf is usually a symlink into the first.
    "/run/systemd/resolve",
    "/run/nscd",
    "/run/wrappers",
    "/run/opengl-driver",
    "/run/booted-system",
];

// Device nodes bound back in after --dev.
const DEV_BIND: &[&str] = &["/dev/kvm", "/dev/bus/usb"];

// Temp directories, read-write (programs write temp files and read them back).
// $TMPDIR is added on top when it names something else.
const RW_ABSOLUTE: &[&str] = &["/tmp", "/var/tmp"];

// The scratch directories a session shares with the host. These come from the
// caller's environment rather than from policy, so they are gathered once and
// passed in -- which also keeps the plan a pure function of its arguments.
#[derive(Default)]
pub struct Scratch {
    // Read-write and shared with the host, like /tmp itself.
    pub shared: Vec<PathBuf>,
    // Present but the sandbox's own: an empty tmpfs where the host's would
    // hold live agent sockets.
    pub private: Vec<PathBuf>,
    // Individual paths that must not be reachable even though a mount above
    // carries them in.
    pub masked: Vec<PathBuf>,
}

impl Scratch {
    pub fn from_env() -> Self {
        let mut s = Scratch::default();
        // A private XDG_RUNTIME_DIR rather than the host's: tools expect the
        // directory to exist, and the host's holds live agent sockets
        // (ssh-agent, gpg-agent, keyrings) that would hand out exactly the
        // credentials the policy is built to keep away.
        if let Some(run) = std::env::var_os("XDG_RUNTIME_DIR") {
            let run = PathBuf::from(run);
            if run.is_absolute() {
                s.private.push(run);
            }
        }
        if let Some(tmp) = std::env::var_os("TMPDIR") {
            let tmp = PathBuf::from(tmp);
            if tmp.is_absolute() && !RW_ABSOLUTE.iter().any(|p| Path::new(p) == tmp) {
                s.shared.push(tmp);
            }
        }
        // The live agent sockets, whose entire purpose is to hand out the
        // credentials the rest of this policy keeps away: ssh-agent signs with
        // keys ~/.ssh never has to expose, and a docker daemon socket is root
        // on the host. A private XDG_RUNTIME_DIR hides the ones that live
        // there, but ssh-agent's is conventionally a directory under /tmp,
        // which is shared. Unlike Seatbelt, a mount namespace has no rule that
        // denies a path back out of a mount -- so the socket is covered over.
        for var in ["SSH_AUTH_SOCK", "DOCKER_HOST"] {
            let Ok(value) = std::env::var(var) else {
                continue;
            };
            let path = PathBuf::from(value.strip_prefix("unix://").unwrap_or(&value));
            if path.is_absolute() {
                s.masked.push(path);
            }
        }
        s
    }
}

// Where the broker's grant carrier is bound. The launcher receives paths
// beneath it as grant tokens and binds them onto the real ones.
pub const GRANT_ROOT: &str = "/run/aibox/grants";

// The sandbox's $HOME: a real directory, private to aibox, that persists
// between sessions. See the module comment for why it is not a tmpfs.
pub const OVERLAY_HOME: &str = ".aibox/home";

#[derive(Debug, PartialEq)]
pub enum Mount {
    // A host path, read-only inside. Skipped when the source is missing.
    Ro(PathBuf, PathBuf),
    // A host path, read-write inside. Skipped when the source is missing.
    Rw(PathBuf, PathBuf),
    // A host path that must exist; the session is pointless without it.
    RwRequired(PathBuf, PathBuf),
    // An empty tmpfs, hiding whatever the mount underneath holds.
    Empty(PathBuf),
    // /dev/null over a single file, hiding its contents the same way.
    Masked(PathBuf),
}

impl Mount {
    // The host path this mount carries into the sandbox, if any. Masks carry
    // nothing in -- that is what they are for.
    fn source(&self) -> Option<&Path> {
        match self {
            Mount::Ro(s, _) | Mount::Rw(s, _) | Mount::RwRequired(s, _) => Some(s),
            Mount::Empty(_) | Mount::Masked(_) => None,
        }
    }

    fn args(&self) -> Vec<String> {
        let two = |flag: &str, a: &Path, b: &Path| {
            vec![
                flag.to_string(),
                a.to_string_lossy().into_owned(),
                b.to_string_lossy().into_owned(),
            ]
        };
        match self {
            Mount::Ro(s, d) => two("--ro-bind-try", s, d),
            Mount::Rw(s, d) => two("--bind-try", s, d),
            Mount::RwRequired(s, d) => two("--bind", s, d),
            Mount::Empty(d) => vec!["--tmpfs".to_string(), d.to_string_lossy().into_owned()],
            Mount::Masked(d) => two("--ro-bind", Path::new("/dev/null"), d),
        }
    }
}

// The mount list for a session, in the order bwrap must apply it: a mount
// always lands on top of the one that carries its parent directory.
pub fn mounts(workspace: &str, home: &str, extra_rw: &[String], scratch: &Scratch) -> Vec<Mount> {
    let home = Path::new(home);
    let mut m = Vec::new();

    // $HOME first: everything below is stacked onto the overlay.
    m.push(Mount::RwRequired(home.join(OVERLAY_HOME), home.to_path_buf()));

    for path in RO_ABSOLUTE {
        m.push(Mount::Ro(PathBuf::from(path), PathBuf::from(path)));
    }
    for path in RW_ABSOLUTE {
        m.push(Mount::Rw(PathBuf::from(path), PathBuf::from(path)));
    }
    for path in &scratch.private {
        m.push(Mount::Empty(path.clone()));
    }
    for path in &scratch.shared {
        m.push(Mount::Rw(path.clone(), path.clone()));
    }

    for rel in RO_HOME {
        let full = home.join(rel);
        m.push(Mount::Ro(full.clone(), full));
    }
    for rel in RW_HOME {
        let full = home.join(rel);
        m.push(Mount::Rw(full.clone(), full));
    }
    for rel in RW_HOME_ALWAYS {
        let full = home.join(rel);
        // A bind needs a source, so these are created rather than skipped.
        let _ = std::fs::create_dir_all(&full);
        m.push(Mount::Rw(full.clone(), full));
    }

    // The workspace, and the enclosing repository's shared directories.
    let ws = PathBuf::from(workspace);
    m.push(Mount::RwRequired(ws.clone(), ws));
    if let Some(root) = repo::root(workspace) {
        for name in repo::SHARED {
            let full = root.join(name);
            m.push(Mount::Rw(full.clone(), full));
        }
        let git = root.join(".git");
        if git.is_file() {
            if let Some(common) = repo::worktree_common_git(&git) {
                m.push(Mount::Rw(common.clone(), common));
            }
        }
    }

    for path in extra_rw {
        let p = PathBuf::from(path);
        m.push(Mount::Rw(p.clone(), p));
    }

    // Masks last: a deeper, later mount is what carves a secret back out of an
    // allowed tree.
    for rel in SENSITIVE_HOME {
        let full = home.join(rel);
        if !carried(&m, Some(home), &full) {
            continue;
        }
        match std::fs::symlink_metadata(&full) {
            Ok(meta) if meta.is_dir() => m.push(Mount::Empty(full)),
            Ok(_) => m.push(Mount::Masked(full)),
            Err(_) => {}
        }
    }
    for path in &scratch.masked {
        if !carried(&m, None, path) {
            continue;
        }
        match std::fs::symlink_metadata(path) {
            Ok(meta) if meta.is_dir() => m.push(Mount::Empty(path.clone())),
            // A path that is not there yet still gets a mask: the session's own
            // control socket is bound after the plan is written.
            _ => m.push(Mount::Masked(path.clone())),
        }
    }
    m
}

// True when some already-planned mount would carry this path into the sandbox.
// A secret nothing reaches needs no mask -- which is why the overlay home
// matches nothing for a home path: it carries ~/.aibox/home, not the real home,
// so every untouched dotfile beside it stays out by simply not being mounted.
//
// `within` restricts which mounts count. The home secrets pass the home
// directory, because a home path that showed up under some unrelated tree would
// be a coincidence of one machine's layout rather than a rule; an agent socket
// passes None, since it is reachable however it got there.
fn carried(mounts: &[Mount], within: Option<&Path>, path: &Path) -> bool {
    mounts
        .iter()
        .filter_map(Mount::source)
        .filter(|src| within.is_none_or(|root| src.starts_with(root)))
        .any(|src| path.starts_with(src) && path != src)
}

// The full bwrap argument vector, one argument per line. The broker appends
// the session's grant carrier and the launcher command.
pub fn generate(
    workspace: &str,
    home: &str,
    protected: &[String],
    extra_rw: &[String],
    scratch: &Scratch,
) -> Result<String, String> {
    let mounts = mounts(workspace, home, extra_rw, scratch);
    // The state root holds the capability that authorizes the broker. Unlike
    // Seatbelt, there is no rule that can deny a path back out of a mount, so
    // the only defence is that nothing carries it in -- checked, not assumed.
    for path in protected {
        if let Some(m) = mounts
            .iter()
            .find(|m| m.source().is_some_and(|src| Path::new(path).starts_with(src)))
        {
            return Err(format!(
                "{path} must stay outside the sandbox, but {} would carry it in",
                m.source().unwrap_or(Path::new("?")).display()
            ));
        }
    }

    let mut args: Vec<String> = vec![
        // No network isolation, by design; the workspace is the unit of
        // containment, not the machine.
        "--unshare-user".to_string(),
        // A private PID namespace is not optional: mounting a fresh /proc
        // requires one, and binding the host's would expose every same-user
        // process's environment. bwrap runs a reaping init as PID 1 there.
        "--unshare-pid".to_string(),
        "--die-with-parent".to_string(),
    ];
    for m in &mounts {
        args.extend(m.args());
    }
    args.extend(["--proc".to_string(), "/proc".to_string()]);
    args.extend(["--dev".to_string(), "/dev".to_string()]);
    // Bound after --dev, which replaces whatever /dev held: the Android
    // emulator needs KVM, and adb needs the USB bus to reach a real device.
    for dev in DEV_BIND {
        args.extend([
            "--dev-bind-try".to_string(),
            dev.to_string(),
            dev.to_string(),
        ]);
    }
    args.extend(["--chdir".to_string(), workspace.to_string()]);

    if let Some(bad) = args.iter().find(|a| a.contains('\n')) {
        return Err(format!("path contains a newline: {bad}"));
    }
    let mut out = args.join("\n");
    out.push('\n');
    Ok(out)
}

// Reads back a plan written by `generate`.
pub fn parse(text: &str) -> Vec<String> {
    text.lines().map(str::to_string).collect()
}

pub fn run(args: &[String]) -> i32 {
    let ws = match args.first() {
        Some(w) if Path::new(w).is_absolute() => w,
        _ => {
            eprintln!("usage: aibox profile <workspace-abs-path> [--protect <abs-dir>] [--rw <abs-dir>] [--sock <abs-path>]...");
            return 2;
        }
    };

    let mut protected = Vec::new();
    let mut extra_rw = Vec::new();
    let mut scratch = Scratch::from_env();
    let mut i = 1;
    while i < args.len() {
        let option = &args[i];
        i += 1;
        let Some(path) = args.get(i) else {
            eprintln!("aibox profile: {option} requires an absolute directory");
            return 2;
        };
        i += 1;
        if !Path::new(path).is_absolute() {
            eprintln!("aibox profile: path must be absolute: {path}");
            return 2;
        }
        match option.as_str() {
            "--protect" => protected.push(path.clone()),
            "--rw" => extra_rw.push(path.clone()),
            "--sock" => scratch.masked.push(PathBuf::from(path)),
            _ => {
                eprintln!("aibox profile: unknown option {option}");
                return 2;
            }
        }
    }

    let home = std::env::var("HOME").unwrap_or_default();
    // The overlay home is the sandbox's $HOME; without it there is nothing to
    // bind and every write below $HOME would land in a tmpfs.
    let overlay = Path::new(&home).join(OVERLAY_HOME);
    if let Err(e) = std::fs::create_dir_all(&overlay) {
        eprintln!("aibox profile: create {}: {e}", overlay.display());
        return 1;
    }
    match generate(ws, &home, &protected, &extra_rw, &scratch) {
        Ok(plan) => {
            print!("{plan}");
            0
        }
        Err(e) => {
            eprintln!("aibox profile: {e}");
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{generate, mounts, Mount, Scratch, GRANT_ROOT, OVERLAY_HOME};
    use std::path::{Path, PathBuf};

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("aibox-plan-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn plan(workspace: &Path, home: &Path) -> String {
        generate(
            &workspace.to_string_lossy(),
            &home.to_string_lossy(),
            &[],
            &[],
            &Scratch::default(),
        )
        .expect("plan")
    }

    // $HOME inside the sandbox is a real directory of aibox's own, so that the
    // atomic writes tools do there land somewhere that survives the session.
    #[test]
    fn home_is_the_overlay_not_the_real_one() {
        let base = scratch("home");
        let (home, ws) = (base.join("home"), base.join("ws"));
        std::fs::create_dir_all(&ws).unwrap();
        std::fs::create_dir_all(home.join(OVERLAY_HOME)).unwrap();

        let m = mounts(
            &ws.to_string_lossy(),
            &home.to_string_lossy(),
            &[],
            &Scratch::default(),
        );
        assert_eq!(
            m[0],
            Mount::RwRequired(home.join(OVERLAY_HOME), home.clone())
        );
        std::fs::remove_dir_all(&base).unwrap();
    }

    // The devcontainer hid these behind a fresh volume. Here the tree they sit
    // in is granted, so a later, deeper mount carves them back out -- and only
    // those: a secret nothing mounts needs no rule, and must not get one,
    // because bwrap would create the destination it was told to cover.
    #[test]
    fn masks_only_secrets_inside_an_allowed_tree() {
        let base = scratch("mask");
        let (home, ws) = (base.join("home"), base.join("ws"));
        std::fs::create_dir_all(&ws).unwrap();
        std::fs::create_dir_all(home.join(OVERLAY_HOME)).unwrap();
        std::fs::create_dir_all(home.join(".cargo")).unwrap();
        std::fs::write(home.join(".cargo/credentials.toml"), "token").unwrap();
        std::fs::create_dir_all(home.join(".rustup/secrets")).unwrap();
        std::fs::create_dir_all(home.join(".ssh")).unwrap();
        std::fs::write(home.join(".netrc"), "machine x").unwrap();

        let text = plan(&ws, &home);
        assert!(text.contains(&format!(
            "--ro-bind\n/dev/null\n{}/.cargo/credentials.toml\n",
            home.display()
        )));
        assert!(text.contains(&format!("--tmpfs\n{}/.rustup/secrets\n", home.display())));
        // Nothing mounts the real home, so these are already absent.
        assert!(!text.contains(&format!("{}/.ssh", home.display())));
        assert!(!text.contains(&format!("{}/.netrc", home.display())));
        std::fs::remove_dir_all(&base).unwrap();
    }

    // A mount namespace has no rule that denies a path back out of a mount, so
    // the one shared temp directory an ssh-agent socket conventionally sits in
    // has to be covered over where the environment points at it.
    #[test]
    fn masks_an_agent_socket_a_shared_mount_would_reach() {
        let base = scratch("agent");
        let (home, ws, tmp) = (base.join("home"), base.join("ws"), base.join("tmp"));
        std::fs::create_dir_all(&ws).unwrap();
        std::fs::create_dir_all(home.join(OVERLAY_HOME)).unwrap();
        std::fs::create_dir_all(tmp.join("ssh-XXXX")).unwrap();
        let sock = tmp.join("ssh-XXXX/agent.1");
        std::fs::write(&sock, "").unwrap();

        let sc = Scratch {
            shared: vec![tmp.clone()],
            masked: vec![sock.clone(), PathBuf::from("/var/run/docker.sock")],
            ..Scratch::default()
        };
        let text = generate(
            &ws.to_string_lossy(),
            &home.to_string_lossy(),
            &[],
            &[],
            &sc,
        )
        .expect("plan");
        assert!(text.contains(&format!("--ro-bind\n/dev/null\n{}\n", sock.display())));
        // Nothing mounts /var/run, so that socket needs no mask -- and must not
        // get one, because bwrap would create the destination it was told to
        // cover.
        assert!(!text.contains("docker.sock"));
        std::fs::remove_dir_all(&base).unwrap();
    }

    #[test]
    fn grants_the_enclosing_repository_and_a_worktrees_common_gitdir() {
        let base = scratch("repo");
        let (home, root) = (base.join("home"), base.join("repo"));
        let nested = root.join("packages/aibox");
        std::fs::create_dir_all(home.join(OVERLAY_HOME)).unwrap();
        std::fs::create_dir_all(root.join(".git")).unwrap();
        std::fs::create_dir_all(&nested).unwrap();

        let text = plan(&nested, &home);
        assert!(text.contains(&format!("--bind-try\n{0}/.git\n{0}/.git\n", root.display())));
        assert!(text.contains(&format!(
            "--bind-try\n{0}/.claude\n{0}/.claude\n",
            root.display()
        )));

        // A linked worktree keeps .git as a file pointing into the main repo.
        let wt = base.join("wt");
        std::fs::create_dir_all(&wt).unwrap();
        std::fs::create_dir_all(root.join(".git/worktrees/wt")).unwrap();
        std::fs::write(
            wt.join(".git"),
            format!("gitdir: {}/.git/worktrees/wt\n", root.display()),
        )
        .unwrap();
        let text = plan(&wt, &home);
        assert!(text.contains(&format!("--bind-try\n{0}/.git\n{0}/.git\n", root.display())));
        std::fs::remove_dir_all(&base).unwrap();
    }

    // Seatbelt can deny a path back out of an allow; a mount namespace cannot.
    // The only defence is that nothing carries the state root in.
    #[test]
    fn refuses_a_plan_that_would_carry_the_state_root_in() {
        let base = scratch("protect");
        let (home, ws) = (base.join("home"), base.join("ws"));
        std::fs::create_dir_all(ws.join("state")).unwrap();
        std::fs::create_dir_all(home.join(OVERLAY_HOME)).unwrap();

        let state = ws.join("state").to_string_lossy().into_owned();
        assert!(generate(
            &ws.to_string_lossy(),
            &home.to_string_lossy(),
            &[state],
            &[],
            &Scratch::default(),
        )
        .is_err());
        let elsewhere = format!("/aibox-unmounted-{}/state", std::process::id());
        assert!(generate(
            &ws.to_string_lossy(),
            &home.to_string_lossy(),
            &[elsewhere],
            &[],
            &Scratch::default(),
        )
        .is_ok());
        std::fs::remove_dir_all(&base).unwrap();
    }

    #[test]
    fn starts_the_session_in_the_workspace_with_its_own_namespaces() {
        let base = scratch("shape");
        let (home, ws) = (base.join("home"), base.join("ws"));
        std::fs::create_dir_all(&ws).unwrap();
        std::fs::create_dir_all(home.join(OVERLAY_HOME)).unwrap();

        let text = plan(&ws, &home);
        let args: Vec<&str> = text.lines().collect();
        assert_eq!(args[0], "--unshare-user");
        assert!(args.contains(&"--unshare-pid"));
        assert!(args.contains(&"--die-with-parent"));
        // --dev replaces whatever /dev held, so the device nodes come after it.
        let dev = text.find("--dev\n/dev\n").expect("--dev");
        assert!(dev < text.find("--dev-bind-try\n/dev/kvm\n").expect("kvm"));
        assert_eq!(args[args.len() - 2], "--chdir");
        assert_eq!(args[args.len() - 1], ws.to_string_lossy());
        // Dynamic grants are not part of the static plan; the broker appends
        // the carrier they arrive through.
        assert!(!text.contains(GRANT_ROOT));
        std::fs::remove_dir_all(&base).unwrap();
    }
}
