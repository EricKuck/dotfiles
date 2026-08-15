// Generates the Seatbelt profile for a workspace.
//
// Static protections are baked in as subpath/literal/regex rules: the workspace is
// read-write, the config/cred and cache dirs mirror the devcontainer mounts,
// and system/toolchain paths are read-only. Everything else on disk is denied.
// Dynamic directories never appear here -- they arrive at runtime as consumed
// read-write extensions, honored by the final rule.

use crate::sandbox::EXT_CLASS;
use std::path::{Path, PathBuf};

// Read-only home files the toolchain needs (git config, honored by git and rg).
// Applications mirrors the /Applications rule below for per-user installs. The
// shell startup files are load-bearing for every `sh -c` the harness runs: zsh
// sources .zshenv even non-interactively, so without it each subshell trips a
// denial before it does any work.
const RO_HOME: &[&str] = &[
    ".gitconfig",
    ".config/git",
    ".config/delta",
    ".rustup",
    "Applications",
    ".zshenv",
    ".zshrc",
    ".zprofile",
    ".bashrc",
    ".bash_profile",
    ".profile",
    ".inputrc",
];

// Crown-jewel secrets, hard-denied regardless of any allow -- including the
// global file-read-metadata allow and any dynamic extension grant. These stay
// invisible: not their contents, not even their existence. The last three
// groups are secret-bearing files that sit INSIDE otherwise-allowed cache dirs
// (~/.gradle, ~/.m2, ~/.cargo) -- the devcontainer hid these behind a fresh
// volume; here a deeper, more-specific deny carves them back out. .npmrc is a
// file, not a directory; npm keeps its registry tokens there, outside ~/.npm.
const SENSITIVE_HOME: &[&str] = &[
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
    "Library/Keychains",
    ".gradle/gradle.properties",
    ".m2/settings.xml",
    ".m2/settings-security.xml",
    ".cargo/credentials",
    ".cargo/credentials.toml",
    ".rustup/credentials",
    ".rustup/credentials.toml",
    ".rustup/secrets",
    ".rustup/secrets.toml",
];

// Config/cred/cache locations mirrored from the devcontainer, relative to $HOME.
const RW_HOME: &[&str] = &[
    ".claude",
    ".claude.json",
    ".pi",
    ".codex",
    ".config/opencode",
    ".config/fish",
    ".local/share/opencode",
    ".local/share/fish",
    ".gradle",
    ".m2",
    "go",
    ".clipboard-images",
    ".aibox/activity",
    "Library/Android/sdk",
    "Library/Application Support/kotlin",
    "Library/org.swift.swiftpm",
    "Library/Caches/org.swift.swiftpm",
    "Library/Caches/go-build",
    ".konan",
    ".skiko",
];

// Toolchain caches and local app data need persistent write access. These are
// emitted even when absent so tools can create them on first use: cargo writes
// its registry cache to ~/.cargo on the first fetch, and npm creates ~/.npm
// lazily (the credential files inside both are carved out in SENSITIVE_HOME).
const RW_HOME_ALWAYS: &[&str] = &[
    ".cargo",
    ".npm",
    ".cache/nix",
    "Library/Application Support/rtk",
];
const RW_ABSOLUTE: &[&str] = &["/opt/homebrew"];

// Directories an enclosing repository shares with the workspace. A workspace
// nested BELOW the repo root (~/.config/nix/packages/aibox inside the
// ~/.config/nix repo) resolves both of these above its own subtree: git reads
// .git on every command, and the harness and its tooling read project settings
// from .claude. Granting them by name leaves the rest of the repository denied
// -- its files, its listing, and any sibling secret.
const REPO_SHARED: &[&str] = &[".git", ".claude"];

// Non-file operations the profile allows outright, exactly as emitted. No
// network isolation by design. ipc-posix-shm is needed by CoreFoundation
// preferences and the notification center.
//
// The denial filter matches against this same table, so a rule can never be
// allowed here and still be recorded as an aibox denial.
const ALLOWED_OPS: &[&str] = &[
    "process*",
    "sysctl-read",
    "mach*",
    "signal",
    "iokit*",
    "system*",
    "network*",
    "ipc-posix-shm*",
    "pseudo-tty",
];

// CoreFoundation reads the global preference domain when it initializes, so
// every Rust, Node and CLI tool in the sandbox trips this before running any
// code of its own. Scoped to that one domain deliberately: a bare
// (allow user-preference-read) would let a sandboxed process read ANY
// preference plist through cfprefsd, routing around the file rules that keep
// ~/Library/Preferences denied.
const ALLOWED_PREFERENCE_DOMAIN: &str = "kCFPreferencesAnyApplication";

// System + toolchain, read-only. On nix-darwin the PATH binaries live in the
// immutable /nix/store and /run/current-system, so read access there is safe.
// /Applications is a toolchain location too, not just a place apps sit: cc
// shells out to xcrun, which dlopens libxcrun from the Xcode bundle, and a
// terminal that ships a CLI and a terminfo entry (Supacode, Ghostty) keeps
// both inside its own bundle. App bundles are signed vendor code rather than
// user data, so this is no wider than the /Library rule beside it.
const RO_ABSOLUTE: &[&str] = &[
    "/usr",
    "/bin",
    "/sbin",
    "/System",
    "/Library",
    "/private/etc",
    "/private/var/db",
    "/nix",
    "/run/current-system",
    "/opt",
    "/Applications",
];

// Listing /dev -- the directory node itself, never the device files under it --
// is how devname(3) turns a tty's device number back into a name. Without it
// `ps -o tty=` answers `??` for every process, and the agent presence hooks
// lose the terminal they signal the host app on.
const RO_LITERAL: &[&str] = &["/", "/dev", "/dev/zero", "/dev/random", "/dev/urandom"];

// Temp directories, read-write (programs write temp files and read them back).
const RW_TMP: &[&str] = &["/private/tmp", "/private/var/folders"];

// Terminal + std device files, read-write. stdio is a pty (/dev/ttysNNN);
// programs fstat these fds at startup, so metadata access here is load-bearing.
const RW_DEV_LITERAL: &[&str] = &["/dev/null", "/dev/tty", "/dev/ptmx", "/dev/dtracehelper"];
const IOCTL_LITERAL: &[&str] = &["/dev/null", "/dev/dtracehelper"];
const TTY_REGEX: &str = "^/dev/ttys[0-9]+$";

pub fn generate(workspace: &str, home: &str, protected: &[String], extra_rw: &[String]) -> String {
    // Emit Seatbelt denials to the macOS unified log. Every broker streams
    // those events into its session's structured denial log.
    let mut s = String::from("(version 1)\n(debug deny)\n(deny default)\n\n");

    for op in ALLOWED_OPS {
        s.push_str(&format!("(allow {op})\n"));
    }
    s.push_str(&format!(
        "(allow user-preference-read (preference-domain \"{ALLOWED_PREFERENCE_DOMAIN}\"))\n\n"
    ));

    s.push_str("(allow file-read*\n");
    for path in RO_ABSOLUTE {
        s.push_str(&format!("  (subpath \"{path}\")\n"));
    }
    for path in RO_LITERAL {
        s.push_str(&format!("  (literal \"{path}\")\n"));
    }
    s.push_str(")\n\n");

    s.push_str("(allow file-read* file-write*\n");
    for path in RW_TMP {
        s.push_str(&format!("  (subpath \"{path}\")\n"));
    }
    for path in RW_DEV_LITERAL {
        s.push_str(&format!("  (literal \"{path}\")\n"));
    }
    s.push_str("  (subpath \"/dev/fd\")\n");
    s.push_str(&format!("  (regex #\"{TTY_REGEX}\"))\n"));
    s.push_str("(allow file-ioctl\n");
    for path in IOCTL_LITERAL {
        s.push_str(&format!("  (literal \"{path}\")\n"));
    }
    s.push_str(&format!("  (regex #\"{TTY_REGEX}\"))\n\n"));

    // Metadata (stat) is allowed globally: it enables path resolution and the
    // stat-based checks tools run at startup, while file CONTENTS and directory
    // LISTINGS stay governed by file-read-data below -- so secrets and the shape
    // of denied directories are not readable, only the existence of a named path.
    s.push_str("(allow file-read-metadata)\n\n");

    // Workspace + config/cred/cache, read-write.
    s.push_str("(allow file-read* file-write*\n");
    s.push_str(&format!("  (subpath \"{}\")\n", escape(workspace)));
    for path in extra_rw {
        s.push_str(&format!("  (subpath \"{}\")\n", escape(path)));
    }
    for rel in RW_HOME_ALWAYS {
        s.push_str(&format!(
            "  (subpath \"{}\")\n",
            escape(&format!("{home}/{rel}"))
        ));
    }
    for path in RW_ABSOLUTE {
        s.push_str(&format!("  (subpath \"{}\")\n", escape(path)));
    }
    for rel in RW_HOME {
        let full = format!("{home}/{rel}");
        let p = Path::new(&full);
        if !p.exists() {
            continue;
        }
        // A file (e.g. .claude.json) must be a literal; subpath only matches dirs.
        if p.is_dir() {
            s.push_str(&format!("  (subpath \"{}\")\n", escape(&full)));
        } else {
            s.push_str(&format!("  (literal \"{}\")\n", escape(&full)));
        }
    }
    s.push_str(")\n\n");

    // The enclosing repository's shared directories, resolved from the
    // workspace rather than matched by shape. An earlier version granted every
    // .git on the machine through a `.*/\.git(/.*)?$` regex, which reached far
    // past what a session needs: any repository anywhere on disk, including one
    // sitting inside a directory that is otherwise denied. Resolving the root
    // instead grants exactly the repo this workspace belongs to, and lets
    // .claude ride the same rule -- a project's settings live beside its .git
    // and are read on the same every-command cadence.
    if let Some(root) = repo_root(workspace) {
        s.push_str("(allow file-read* file-write*\n");
        for name in REPO_SHARED {
            s.push_str(&format!(
                "  (subpath \"{}\")\n",
                escape(&root.join(name).to_string_lossy())
            ));
        }
        // A repo root that is itself a linked worktree keeps .git as a FILE
        // holding `gitdir: <main>/.git/worktrees/<name>`; the subpath above
        // matches nothing then, and every command still reaches into the main
        // repository's .git, which is nowhere near the workspace.
        let git = root.join(".git");
        if git.is_file() {
            s.push_str(&format!(
                "  (literal \"{}\")\n",
                escape(&git.to_string_lossy())
            ));
            if let Some(common) = worktree_common_git(&git) {
                s.push_str(&format!(
                    "  (subpath \"{}\")\n",
                    escape(&common.to_string_lossy())
                ));
            }
        }
        s.push_str(")\n\n");
    }

    // claude persists ~/.claude.json by writing a sibling lock/temp file and
    // renaming over it, so the family (not just the file) must be writable.
    s.push_str(&format!(
        "(allow file-read* file-write* (regex #\"^{}\"))\n\n",
        regex_escape(&format!("{home}/.claude.json"))
    ));

    // Read-only home files (git config etc.).
    let mut ro = String::new();
    for rel in RO_HOME {
        let full = format!("{home}/{rel}");
        let p = Path::new(&full);
        if !p.exists() {
            continue;
        }
        if p.is_dir() {
            ro.push_str(&format!("  (subpath \"{}\")\n", escape(&full)));
        } else {
            ro.push_str(&format!("  (literal \"{}\")\n", escape(&full)));
        }
    }
    if !ro.is_empty() {
        s.push_str("(allow file-read*\n");
        s.push_str(&ro);
        s.push_str(")\n\n");
    }

    // The one widening mechanism: consumed read-write extensions.
    s.push_str(&format!(
        "(allow file-read* file-write* (extension \"{EXT_CLASS}\"))\n\n"
    ));

    // Hard-deny the secrets. file-read-metadata is named EXPLICITLY: SBPL lets a
    // more-specific operation win, so a broad `(deny file*)` would lose the stat
    // to the global `(allow file-read-metadata)` and leak these paths' existence.
    // A deeper subpath also out-specifies the ~/.gradle and ~/.m2 rw allows, so
    // the secret files inside them are carved out while the caches stay writable.
    s.push_str("(deny file-read* file-read-metadata file-write* file-ioctl\n");
    for rel in SENSITIVE_HOME {
        s.push_str(&format!(
            "  (subpath \"{}\")\n",
            escape(&format!("{home}/{rel}"))
        ));
    }
    // State contains the capability that authorizes the external broker.  It
    // must remain unavailable even if a user dynamically grants a parent path.
    for path in protected {
        s.push_str(&format!("  (subpath \"{}\")\n", escape(path)));
    }
    s.push_str(")\n");
    s
}

// The nearest ancestor of the workspace holding a .git, the workspace itself
// included. None when the workspace is not inside a repository at all.
fn repo_root(workspace: &str) -> Option<PathBuf> {
    let mut dir = Some(Path::new(workspace));
    while let Some(d) = dir {
        if d.join(".git").exists() {
            return Some(d.to_path_buf());
        }
        dir = d.parent();
    }
    None
}

// The main repository's .git, read out of a linked worktree's .git file.
fn worktree_common_git(git: &Path) -> Option<PathBuf> {
    let text = std::fs::read_to_string(git).ok()?;
    let target = text.lines().next()?.trim().strip_prefix("gitdir:")?.trim();
    let mut dir = Path::new(target);
    if !dir.is_absolute() {
        return None;
    }
    // The recorded gitdir points at <main>/.git/worktrees/<name>; walk back up
    // to the .git that contains it.
    while dir.file_name()? != Path::new(".git").as_os_str() {
        dir = dir.parent()?;
    }
    Some(dir.to_path_buf())
}

// True when the profile allows this operation on this path outright, which
// means the denial cannot have come from an aibox sandbox. Seatbelt's
// `(debug deny)` events land in the machine-wide unified log, where macOS's own
// sandboxed daemons produce a constant background of denials against their own
// profiles; the broker uses this to drop those instead of recording them as
// ours. Because it reads the very tables the profile is emitted from, a rule
// cannot be allowed above and still be logged here.
//
// Only the static, absolute rules are consulted. Home-relative and workspace
// paths are left out on purpose: those denials are the ones worth seeing. In
// particular the global (allow file-read-metadata) is NOT applied, because the
// sensitive-home deny out-specifies it -- a stat of ~/.ssh is a real denial.
pub fn would_allow(operation: &str, path: &str) -> bool {
    if ALLOWED_OPS.iter().any(|op| match op.strip_suffix('*') {
        Some(prefix) => operation.starts_with(prefix),
        None => operation == *op,
    }) {
        return true;
    }
    if operation == "user-preference-read" {
        // The unified log lowercases the domain it reports.
        return path.eq_ignore_ascii_case(ALLOWED_PREFERENCE_DOMAIN);
    }
    let read = operation.starts_with("file-read");
    let write = operation.starts_with("file-write");
    if read && (RO_LITERAL.contains(&path) || under_any(path, RO_ABSOLUTE)) {
        return true;
    }
    if (read || write)
        && (under_any(path, RW_TMP)
            || under_any(path, RW_ABSOLUTE)
            || RW_DEV_LITERAL.contains(&path)
            || under(path, "/dev/fd")
            || is_tty(path))
    {
        return true;
    }
    operation == "file-ioctl" && (IOCTL_LITERAL.contains(&path) || is_tty(path))
}

fn under(path: &str, prefix: &str) -> bool {
    path == prefix || (path.starts_with(prefix) && path.as_bytes().get(prefix.len()) == Some(&b'/'))
}

fn under_any(path: &str, prefixes: &[&str]) -> bool {
    prefixes.iter().any(|prefix| under(path, prefix))
}

fn is_tty(path: &str) -> bool {
    match path.strip_prefix("/dev/ttys") {
        Some(unit) => !unit.is_empty() && unit.bytes().all(|b| b.is_ascii_digit()),
        None => false,
    }
}

// Escapes a literal string for embedding in an SBPL #"..." regex.
fn regex_escape(s: &str) -> String {
    let mut out = String::new();
    for c in s.chars() {
        if "\\.^$|?*+()[]{}".contains(c) {
            out.push('\\');
        }
        out.push(c);
    }
    out
}

// SBPL string literals are double-quoted; backslash and quote need escaping.
fn escape(s: &str) -> String {
    s.replace('\\', "\\\\").replace('"', "\\\"")
}

pub fn run(args: &[String]) -> i32 {
    let ws = match args.first() {
        Some(w) if Path::new(w).is_absolute() => w,
        _ => {
            eprintln!("usage: aibox profile <workspace-abs-path> [--protect <abs-dir>] [--rw <abs-dir>]...");
            return 2;
        }
    };

    let mut protected = Vec::new();
    let mut extra_rw = Vec::new();
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
            _ => {
                eprintln!("aibox profile: unknown option {option}");
                return 2;
            }
        }
    }

    let home = std::env::var("HOME").unwrap_or_default();
    print!("{}", generate(ws, &home, &protected, &extra_rw));
    0
}

#[cfg(test)]
mod tests {
    use super::{generate, repo_root, worktree_common_git, would_allow};
    use std::path::Path;

    #[test]
    fn allows_operations_the_profile_grants_outright() {
        assert!(would_allow("mach-lookup", "com.apple.bird"));
        assert!(would_allow("signal", "same-sandbox"));
        assert!(would_allow(
            "network-outbound",
            "/private/var/run/mDNSResponder"
        ));
        assert!(would_allow(
            "iokit-get-properties",
            "iokit-class:AppleAPFSVolume"
        ));
        assert!(would_allow("system-fsctl", "whatever"));
        // Never granted by the profile, so a denial is genuinely a sandbox miss.
        assert!(!would_allow("syscall-unix", "545"));
        assert!(!would_allow(
            "user-preference-write",
            "com.apple.messages.commsafety"
        ));
    }

    #[test]
    fn allows_only_the_global_preference_domain() {
        assert!(would_allow(
            "user-preference-read",
            "kcfpreferencesanyapplication"
        ));
        assert!(!would_allow("user-preference-read", "com.apple.triald"));
    }

    #[test]
    fn allows_reads_under_the_static_system_paths() {
        assert!(would_allow(
            "file-read-data",
            "/private/var/db/os_eligibility/eligibility.plist"
        ));
        assert!(would_allow(
            "file-read-data",
            "/Applications/Ghostty.app/Contents/Info.plist"
        ));
        assert!(would_allow("file-read-metadata", "/"));
        assert!(would_allow("file-read-data", "/dev"));
        assert!(would_allow("file-write-data", "/private/tmp/x"));
        assert!(would_allow("file-read-data", "/dev/dtracehelper"));
        assert!(would_allow("file-ioctl", "/dev/ttys004"));
        // A prefix that merely shares a name component is a different path.
        assert!(!would_allow("file-read-data", "/usrlocal/x"));
        assert!(!would_allow("file-write-data", "/Applications/Ghostty.app"));
        assert!(!would_allow("file-read-data", "/dev/ttysabc"));
    }

    // The denials worth keeping: a stat of a hard-denied secret is a real event,
    // so the global file-read-metadata allow must not be applied here.
    #[test]
    fn keeps_home_denials() {
        assert!(!would_allow(
            "file-read-metadata",
            "/Users/eric/Library/Keychains"
        ));
        assert!(!would_allow("file-read-data", "/Users/eric/.npmrc"));
        assert!(!would_allow("file-read-data", "/Users/eric"));
    }

    #[test]
    fn resolves_the_enclosing_repository() {
        let tmp = std::env::temp_dir().join(format!("aibox-profile-repo-{}", std::process::id()));
        let nested = tmp.join("packages/aibox");
        std::fs::create_dir_all(tmp.join(".git")).unwrap();
        std::fs::create_dir_all(&nested).unwrap();

        assert_eq!(repo_root(&nested.to_string_lossy()).unwrap(), tmp);

        let sb = generate(&nested.to_string_lossy(), "/Users/nobody", &[], &[]);
        assert!(sb.contains(&format!("(subpath \"{}/.git\")", tmp.display())));
        assert!(sb.contains(&format!("(subpath \"{}/.claude\")", tmp.display())));
        // The universal rule this replaced granted every .git on the machine.
        assert!(!sb.contains(r"\.git(/"));

        std::fs::remove_dir_all(&tmp).unwrap();
    }

    #[test]
    fn resolves_a_linked_worktrees_common_gitdir() {
        let tmp = std::env::temp_dir().join(format!("aibox-profile-wt-{}", std::process::id()));
        let ws = tmp.join("ws");
        std::fs::create_dir_all(&ws).unwrap();
        std::fs::create_dir_all(tmp.join("main/.git/worktrees/ws")).unwrap();
        std::fs::write(
            ws.join(".git"),
            format!("gitdir: {}/main/.git/worktrees/ws\n", tmp.display()),
        )
        .unwrap();

        let common = worktree_common_git(&ws.join(".git")).unwrap();
        assert_eq!(common, tmp.join("main/.git"));

        let sb = generate(&ws.to_string_lossy(), "/Users/nobody", &[], &[]);
        assert!(sb.contains(&format!("(subpath \"{}/main/.git\")", tmp.display())));
        assert!(sb.contains(&format!("(literal \"{}/.git\")", ws.display())));

        std::fs::remove_dir_all(&tmp).unwrap();
    }

    #[test]
    fn workspace_outside_any_repository_grants_nothing_extra() {
        let tmp = std::env::temp_dir().join(format!("aibox-profile-bare-{}", std::process::id()));
        std::fs::create_dir_all(&tmp).unwrap();
        let sb = generate(&tmp.to_string_lossy(), "/Users/nobody", &[], &[]);
        assert!(!sb.contains(".claude\")"));
        std::fs::remove_dir_all(&tmp).unwrap();
    }

    #[test]
    fn shell_startup_files_are_read_only_when_present() {
        let home = std::env::temp_dir().join(format!("aibox-profile-home-{}", std::process::id()));
        std::fs::create_dir_all(&home).unwrap();
        std::fs::write(home.join(".zshenv"), "").unwrap();
        let sb = generate("/tmp/ws", &home.to_string_lossy(), &[], &[]);
        assert!(sb.contains(&format!("(literal \"{}/.zshenv\")", home.display())));
        std::fs::remove_dir_all(&home).unwrap();
    }

    #[test]
    fn emits_a_scoped_preference_rule() {
        let sb = generate("/tmp/ws", "/Users/nobody", &[], &[]);
        assert!(sb.contains(
            "(allow user-preference-read (preference-domain \"kCFPreferencesAnyApplication\"))"
        ));
        assert!(!sb.contains("(allow user-preference-read)\n"));
        let _ = Path::new("/");
    }
}
