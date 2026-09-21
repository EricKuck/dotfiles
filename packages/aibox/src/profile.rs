// Generates the Seatbelt profile for a workspace.
//
// Static protections are baked in as subpath/literal/regex rules: the workspace is
// read-write, the config/cred and cache dirs mirror the devcontainer mounts,
// and system/toolchain paths are read-only. Everything else on disk is denied.
// Dynamic directories never appear here -- they arrive at runtime as consumed
// read-write extensions, honored by the final rule.

use crate::repo;
use crate::sandbox::EXT_CLASS;
use std::path::Path;

// Read-only home files the toolchain needs (git config, honored by git and rg).
// ~/.orca/agent-hooks holds the hook scripts every harness turn executes.
// ~/.rustup is deliberately not here but read-write below: rustup installs a
// toolchain into it whenever a repo's rust-toolchain.toml names one it does not
// have. Applications mirrors the /Applications rule below for per-user installs. The
// shell startup files are load-bearing for every `sh -c` the harness runs: zsh
// sources .zshenv even non-interactively, so without it each subshell trips a
// denial before it does any work.
const RO_HOME: &[&str] = &[
    ".gitconfig",
    ".config/git",
    ".config/delta",
    ".terminfo",
    "Applications",
    ".zshenv",
    ".zshrc",
    ".zprofile",
    ".bashrc",
    ".bash_profile",
    ".profile",
    ".inputrc",
    ".orca/agent-hooks",
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
    ".pypirc",
    ".config/op",
    ".config/containers",
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
    ".gem/credentials",
    ".bundle/config",
    "Library/Application Support/pypoetry/auth.toml",
];

// Config/cred/cache locations that must persist, relative to $HOME. Emitted
// whether or not they exist: $HOME itself is not writable, so a toolchain that
// creates its cache on first run needs the rule to be there already -- cargo
// writes ~/.cargo on the first fetch, npm creates ~/.npm lazily, gradle creates
// ~/.gradle. The credential files that sit inside these are carved back out in
// SENSITIVE_HOME.
const RW_HOME: &[&str] = &[
    // Agents and aibox itself.
    ".claude",
    ".claude.json",
    ".pi",
    ".codex",
    ".config/opencode",
    ".local/share/opencode",
    ".config/fish",
    ".local/share/fish",
    ".clipboard-images",
    ".aibox/activity",
    "Library/Application Support/rtk",
    // Orca's hook channel, and only that. Its userData directory is NOT
    // granted: the agent hooks need the endpoint file and the spool they fall
    // back to when the app is not listening, while the rest of that directory
    // holds the app's cookies, its ai-vault, its session authority key and the
    // account credentials it manages -- none of which an agent has any use for.
    "Library/Application Support/orca/agent-hooks",
    // JVM: gradle, maven, the kotlin daemon, sdkman-managed JDKs. ~/.java is
    // where java.util.prefs lands when the JDK has no macOS preferences store.
    ".gradle",
    ".m2",
    ".java",
    ".sdkman",
    ".konan",
    ".skiko",
    "Library/Application Support/kotlin",
    // Android. ~/.android holds the AVDs, the emulator state and the adb key
    // that authorizes a device; without it adb re-prompts on every device.
    ".android",
    "Library/Android/sdk",
    "Android/Sdk",
    // Apple: Xcode derived data, simulator device sets, provisioning profiles,
    // SwiftPM and CocoaPods. ~/Library/Developer covers DerivedData,
    // CoreSimulator, CoreDevice and XCTestDevices in one rule; the signing keys
    // themselves live in the keychain, which stays denied.
    "Library/Developer",
    "Library/MobileDevice",
    "Library/Caches/com.apple.dt.Xcode",
    ".swiftpm",
    "Library/org.swift.swiftpm",
    "Library/Caches/org.swift.swiftpm",
    ".cocoapods",
    "Library/Caches/CocoaPods",
    // Instruments keeps its unpacked instrument packages here and re-extracts
    // into it on every launch. Without it `xctrace list instruments` reports
    // "No instruments found" and every recording exports as malformed.
    "Library/Application Support/Instruments",
    // Python: interpreters, pip/uv/poetry caches, and the --user prefix.
    ".pyenv",
    ".conda",
    ".ipython",
    ".jupyter",
    ".config/pip",
    "Library/Caches/pip",
    ".cache/uv",
    ".local/share/uv",
    ".local/bin",
    ".local/lib",
    "Library/Application Support/pypoetry",
    "Library/Caches/pypoetry",
    // Node: the package managers, their version managers and their caches.
    ".npm",
    ".nvm",
    ".fnm",
    ".volta",
    ".bun",
    ".deno",
    ".yarn",
    ".config/yarn",
    "Library/Caches/Yarn",
    ".corepack",
    ".node-gyp",
    "Library/Caches/node-gyp",
    "Library/pnpm",
    ".local/share/pnpm",
    ".pnpm-store",
    "Library/Caches/ms-playwright",
    // Rust.
    ".cargo",
    ".rustup",
    "Library/Caches/Mozilla.sccache",
    // Go.
    "go",
    "Library/Caches/go-build",
    // Ruby, which iOS work reaches through cocoapods and fastlane.
    ".gem",
    ".bundle",
    // Shared.
    ".cache/nix",
    ".ccache",
];
const RW_ABSOLUTE: &[&str] = &["/opt/homebrew"];

// Non-file operations the profile allows outright, exactly as emitted.
// ipc-posix-shm is needed by CoreFoundation preferences and the notification
// center. Network operations are NOT here; see the socket rules below.
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
    "ipc-posix-shm*",
    "pseudo-tty",
];

// Kernel tracing is configured through sysctl writes, and Instruments does it
// from inside the session: xctrace spawns DTServiceHub, which inherits the
// sandbox and then fails to start with "Could not set the recording priority"
// (the ktrace.background_pid write) while saving a trace with zero rows.
// kdebug is a numbered kern.kdebug.* subtree; kperf, kpc and ktrace are the
// sampler, the performance counters and the session ownership. Every other
// sysctl stays read-only.
// Per-process view settings that vmmap, heap, leaks and footprint write before
// reading a target (vm.self_region_footprint, _page_size, _info_flags, and the
// owned-objects query). They configure only the caller's own view.
const SYSCTL_WRITE_NAMES: &[&str] = &["vm.get_owned_vmobjects"];
const SYSCTL_WRITE_PREFIXES: &[&str] = &["kern.kdebug", "kperf.", "kpc.", "ktrace.", "vm.self_region_"];

// Taking another process's task port -- what Instruments' Allocations attach,
// vmmap, heap and leaks do -- is gated by an Authorization Services right on
// top of the mach rules, and the request fails with -60005 (or "Failed to get
// DYLD info for task") when the right cannot be obtained. These two are the
// only rights allowed; the debug variant is what lldb asks for.
const AUTHORIZATION_RIGHTS: &[&str] = &["system.privilege.taskport", "system.privilege.taskport.debug"];

// Connecting to a unix domain socket is a network-outbound operation carrying
// the socket's path, NOT a file operation -- so a blanket (allow network*)
// hands out every agent socket on the machine (ssh-agent, gpg-agent, the Docker
// daemon, which is root) straight past the SENSITIVE_HOME denies below. IP
// traffic stays unrestricted: the workspace is the unit of containment, not the
// machine. Binding and accepting stay unrestricted too, because creating the
// socket file is already governed by file-write*. Only connecting out is
// allow-listed, and this is that list.
const CONNECT_LITERAL: &[&str] = &[
    "/private/var/run/mDNSResponder",
    "/private/var/run/syslog",
    // usbmuxd is how xcrun devicectl, ios-deploy and libimobiledevice reach a
    // physical iOS device.
    "/private/var/run/usbmuxd",
];
const CONNECT_SUBPATH: &[&str] = &[
    // Local development services put their sockets here (postgres, mysql,
    // redis), and the per-user temp directory is where node, python and
    // CoreSimulator put theirs.
    "/private/tmp",
    "/private/var/folders",
    "/nix/var/nix/daemon-socket",
];

// Home-relative sockets, allowed the same way. The simulator's launchd_sim and
// its per-device services listen inside the device's own data directory.
const CONNECT_HOME: &[&str] = &["Library/Developer/CoreSimulator"];

// launchd vends the per-user agent sockets out of directories it owns, one of
// which sits inside the /private/tmp allow above -- SSH_AUTH_SOCK is
// /private/var/run/com.apple.launchd.<random>/Listeners, and the same shape
// appears under /private/tmp. Named in both places so that widening a temp
// directory later cannot quietly hand the agents back.
const LAUNCHD_SOCKET_DIRS: &[&str] = &["/private/tmp", "/private/var/run"];
const LAUNCHD_SOCKET_PREFIX: &str = "com.apple.launchd.";

// The one launchd-vended socket a session needs: `xcodebuild test` talks to
// its test runner through testmanagerd, and fails with "Failed to establish
// communication with the test runner ... Operation not permitted" without it.
// Matched by its own basename so the agent sockets beside it stay denied.
const LAUNCHD_SOCKET_ALLOWED: &[&str] = &["com.apple.testmanagerd.unix-domain.socket"];

// CoreFoundation reads the global preference domain when it initializes, so
// every Rust, Node and CLI tool in the sandbox trips this before running any
// code of its own. Scoped to that one domain deliberately: a bare
// (allow user-preference-read) would let a sandboxed process read ANY
// preference plist through cfprefsd, routing around the file rules that keep
// ~/Library/Preferences denied.
const ALLOWED_PREFERENCE_DOMAIN: &str = "kCFPreferencesAnyApplication";

// Apple's developer tools keep their settings in these domains and read them
// on every invocation (simctl alone tripped 36,000 denials in a session). The
// IDE domain is also where `defaults write com.apple.dt.Xcode` lands, so the
// manifest-sandbox and similar switches are invisible to xcodebuild without it.
// Reads only; a denied write is a harmless cache miss.
const ALLOWED_PREFERENCE_DOMAINS: &[&str] = &[
    "com.apple.CoreSimulator",
    "com.apple.iphonesimulator",
    "com.apple.dt.Xcode",
    "com.apple.dt.xcodebuild",
    "com.apple.dt.InstrumentsCLI",
    "com.apple.ibtool",
];

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

// Finder and the atomic-save APIs stage into a .TemporaryItems directory at the
// root of whatever volume the file lives on, which is often not the workspace's
// -- a project on an external disk stages at /Volumes/<name>/.TemporaryItems.
// Matching the segment wherever it appears is the only rule that covers them
// all. Two things keep that from being as broad as it reads: Seatbelt matches
// the RESOLVED path, so a symlink named .TemporaryItems cannot reach through
// this into a denied directory, and the hard-denies at the end still outrank
// it, so no .TemporaryItems under ~/.ssh or the state root is reachable.
const TEMPORARY_ITEMS_REGEX: &str = "/\\.TemporaryItems(/|$)";
const TEMPORARY_ITEMS_SEGMENT: &str = ".TemporaryItems";

// Terminal + std device files, read-write. stdio is a pty (/dev/ttysNNN);
// programs fstat these fds at startup, so metadata access here is load-bearing.
// Allocating a pty is three ioctls on the /dev/ptmx master (grantpt, unlockpt,
// ptsname), so opening it read-write is not enough: without the ioctl rule
// openpty(3) fails with EPERM, which is what kills `xcodebuild test` and every
// tool that runs a child under a terminal.
const RW_DEV_LITERAL: &[&str] = &["/dev/null", "/dev/tty", "/dev/ptmx", "/dev/dtracehelper"];
const IOCTL_LITERAL: &[&str] = &["/dev/null", "/dev/ptmx", "/dev/dtracehelper"];
const TTY_REGEX: &str = "^/dev/ttys[0-9]+$";

pub fn generate(
    workspace: &str,
    home: &str,
    protected: &[String],
    extra_rw: &[String],
    sockets: &[String],
) -> String {
    // Emit Seatbelt denials to the macOS unified log. Every broker streams
    // those events into its session's structured denial log.
    let mut s = String::from("(version 1)\n(debug deny)\n(deny default)\n\n");

    for op in ALLOWED_OPS {
        s.push_str(&format!("(allow {op})\n"));
    }
    s.push_str(&format!(
        "(allow user-preference-read (preference-domain \"{ALLOWED_PREFERENCE_DOMAIN}\")"
    ));
    for domain in ALLOWED_PREFERENCE_DOMAINS {
        s.push_str(&format!("\n  (preference-domain \"{domain}\")"));
    }
    s.push_str(")\n");
    s.push_str("(allow authorization-right-obtain\n");
    for name in AUTHORIZATION_RIGHTS {
        s.push_str(&format!("  (right-name \"{name}\")\n"));
    }
    s.push_str(")\n");
    s.push_str("(allow sysctl-write\n");
    for name in SYSCTL_WRITE_PREFIXES {
        s.push_str(&format!("  (sysctl-name-prefix \"{name}\")\n"));
    }
    for name in SYSCTL_WRITE_NAMES {
        s.push_str(&format!("  (sysctl-name \"{name}\")\n"));
    }
    s.push_str(")\n\n");

    s.push_str("(allow network-bind)\n(allow network-inbound)\n");
    s.push_str("(allow network-outbound (remote ip \"*:*\"))\n");
    s.push_str("(allow network-outbound\n");
    for path in CONNECT_LITERAL {
        s.push_str(&format!("  (literal \"{path}\")\n"));
    }
    for path in CONNECT_SUBPATH {
        s.push_str(&format!("  (subpath \"{path}\")\n"));
    }
    for rel in CONNECT_HOME {
        s.push_str(&format!(
            "  (subpath \"{}\")\n",
            escape(&format!("{home}/{rel}"))
        ));
    }
    // A project's own socket -- a dev server, a test fixture -- is as much part
    // of the workspace as its files.
    s.push_str(&format!("  (subpath \"{}\")\n", escape(workspace)));
    for path in extra_rw {
        s.push_str(&format!("  (subpath \"{}\")\n", escape(path)));
    }
    s.push_str(")\n\n");

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
    s.push_str(&format!(
        "(allow file-read* file-write* (regex #\"{TEMPORARY_ITEMS_REGEX}\"))\n"
    ));
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
    for path in RW_ABSOLUTE {
        s.push_str(&format!("  (subpath \"{}\")\n", escape(path)));
    }
    for rel in RW_HOME {
        let full = format!("{home}/{rel}");
        // A file (.claude.json) must be a literal; subpath only matches dirs.
        // A path that is not there yet is one the toolchain has still to create.
        let kind = if Path::new(&full).is_file() {
            "literal"
        } else {
            "subpath"
        };
        s.push_str(&format!("  ({kind} \"{}\")\n", escape(&full)));
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
    if let Some(root) = repo::root(workspace) {
        s.push_str("(allow file-read* file-write*\n");
        for name in repo::SHARED {
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
            if let Some(common) = repo::worktree_common_git(&git) {
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

    // The one widening mechanism: consumed read-write extensions. Sockets ride
    // the same grant, so `aibox allow` on a directory makes the sockets inside
    // it connectable -- which is what that command already means on Linux,
    // where a bind carries a socket in along with everything else. The denies
    // below still outrank it, so no grant can re-open ~/.ssh or the state root.
    s.push_str(&format!(
        "(allow file-read* file-write* network-outbound (extension \"{EXT_CLASS}\"))\n\n"
    ));

    // Hard-deny the secrets. file-read-metadata is named EXPLICITLY: SBPL lets a
    // more-specific operation win, so a broad `(deny file*)` would lose the stat
    // to the global `(allow file-read-metadata)` and leak these paths' existence.
    // A deeper subpath also out-specifies the ~/.gradle and ~/.m2 rw allows, so
    // the secret files inside them are carved out while the caches stay writable.
    // network-outbound is in this list for the same reason it is restricted at
    // all: ~/.docker holds Docker Desktop's daemon socket, ~/.gnupg its agent's.
    s.push_str("(deny file-read* file-read-metadata file-write* file-ioctl network-outbound\n");
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

    // The session's own control socket sits in the per-user temp directory the
    // rule above allows. It is authorized by a capability kept in the denied
    // state root, so reaching it buys nothing -- but nothing inside needs it
    // either: the launcher talks to the broker over an inherited socketpair.
    s.push_str(&format!(
        "(deny network-outbound (regex #\"{}\")\n",
        launchd_socket_regex()
    ));
    for path in sockets {
        s.push_str(&format!("  (literal \"{}\")\n", escape(&canonical(path))));
    }
    s.push_str(")\n");
    s.push_str(&format!(
        "(allow network-outbound (regex #\"{}\"))\n",
        launchd_socket_allowed_regex()
    ));
    s
}

fn launchd_socket_allowed_regex() -> String {
    let names: Vec<String> = LAUNCHD_SOCKET_ALLOWED.iter().map(|n| regex_escape(n)).collect();
    format!("{}[^/]+/({})$", launchd_socket_regex(), names.join("|"))
}

// Seatbelt matches literals against the resolved path, and macOS keeps /tmp,
// /var and /etc as symlinks into /private. The socket itself does not exist yet
// when the profile is written, so its directory is what gets resolved.
fn canonical(path: &str) -> String {
    let p = Path::new(path);
    match (p.parent(), p.file_name()) {
        (Some(dir), Some(name)) => match std::fs::canonicalize(dir) {
            Ok(dir) => dir.join(name).to_string_lossy().into_owned(),
            Err(_) => path.to_string(),
        },
        _ => path.to_string(),
    }
}

// Matches any path inside a launchd-vended per-user socket directory.
fn launchd_socket_regex() -> String {
    let dirs: Vec<String> = LAUNCHD_SOCKET_DIRS.iter().map(|d| regex_escape(d)).collect();
    format!(
        "^({})/{}",
        dirs.join("|"),
        regex_escape(LAUNCHD_SOCKET_PREFIX)
    )
}

// Mirrors launchd_socket_regex and launchd_socket_allowed_regex for the denial filter.
fn is_launchd_socket(path: &str) -> bool {
    LAUNCHD_SOCKET_DIRS.iter().any(|dir| {
        path.strip_prefix(dir)
            .and_then(|rest| rest.strip_prefix('/'))
            .is_some_and(|rest| rest.starts_with(LAUNCHD_SOCKET_PREFIX))
    }) && !is_allowed_launchd_socket(path)
}

fn is_allowed_launchd_socket(path: &str) -> bool {
    let Some((dir, name)) = path.rsplit_once('/') else {
        return false;
    };
    LAUNCHD_SOCKET_ALLOWED.contains(&name)
        && dir
            .rsplit_once('/')
            .is_some_and(|(parent, vendor)| {
                LAUNCHD_SOCKET_DIRS.contains(&parent) && vendor.starts_with(LAUNCHD_SOCKET_PREFIX)
            })
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
        return path.eq_ignore_ascii_case(ALLOWED_PREFERENCE_DOMAIN)
            || ALLOWED_PREFERENCE_DOMAINS.iter().any(|d| path.eq_ignore_ascii_case(d));
    }
    if operation == "network-bind" || operation == "network-inbound" {
        return true;
    }
    if operation == "sysctl-write" {
        return SYSCTL_WRITE_NAMES.contains(&path)
            || SYSCTL_WRITE_PREFIXES.iter().any(|prefix| path.starts_with(prefix));
    }
    if operation == "authorization-right-obtain" {
        return AUTHORIZATION_RIGHTS.contains(&path);
    }
    if operation == "network-outbound" {
        // An endpoint that is not a path is an IP address and port.
        if !path.starts_with('/') {
            return true;
        }
        return !is_launchd_socket(path)
            && (CONNECT_LITERAL.contains(&path) || under_any(path, CONNECT_SUBPATH));
    }
    let read = operation.starts_with("file-read");
    let write = operation.starts_with("file-write");
    if read && (RO_LITERAL.contains(&path) || under_any(path, RO_ABSOLUTE)) {
        return true;
    }
    if (read || write) && is_temporary_items(path) {
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

// Mirrors TEMPORARY_ITEMS_REGEX: the segment, whole, anywhere in the path.
fn is_temporary_items(path: &str) -> bool {
    path.split('/').any(|seg| seg == TEMPORARY_ITEMS_SEGMENT)
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
            eprintln!("usage: aibox profile <workspace-abs-path> [--protect <abs-dir>] [--rw <abs-dir>] [--sock <abs-path>]...");
            return 2;
        }
    };

    let mut protected = Vec::new();
    let mut extra_rw = Vec::new();
    let mut sockets = Vec::new();
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
            "--sock" => sockets.push(path.clone()),
            _ => {
                eprintln!("aibox profile: unknown option {option}");
                return 2;
            }
        }
    }

    let home = std::env::var("HOME").unwrap_or_default();
    print!("{}", generate(ws, &home, &protected, &extra_rw, &sockets));
    0
}

#[cfg(test)]
mod tests {
    use super::{generate, would_allow};
    use crate::repo::{root as repo_root, worktree_common_git};
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

    // The hole this closed: connect(2) on a unix socket is network-outbound, so
    // (allow network*) reached every agent socket on the machine regardless of
    // what the file rules said about the keys behind them.
    #[test]
    fn restricts_unix_sockets_while_leaving_ip_traffic_alone() {
        assert!(would_allow("network-outbound", "17.253.144.10:443"));
        assert!(would_allow("network-bind", "0.0.0.0:8080"));
        assert!(would_allow("network-inbound", "0.0.0.0:8080"));
        assert!(would_allow("network-outbound", "/private/var/run/mDNSResponder"));
        assert!(would_allow("network-outbound", "/private/tmp/.s.PGSQL.5432"));
        assert!(would_allow(
            "network-outbound",
            "/private/var/folders/h8/x/T/pymp-abc/listener"
        ));
        assert!(would_allow("network-outbound", "/private/var/run/usbmuxd"));

        assert!(!would_allow(
            "network-outbound",
            "/private/var/run/com.apple.launchd.AnYCxjG4Es/Listeners"
        ));
        assert!(!would_allow(
            "network-outbound",
            "/private/tmp/com.apple.launchd.0KnX7LEp2i/Listeners"
        ));
        assert!(!would_allow("network-outbound", "/private/var/run/docker.sock"));
        // testmanagerd is vended the same way as the agents, and is the one
        // socket there a session needs.
        assert!(would_allow(
            "network-outbound",
            "/private/tmp/com.apple.launchd.ku5xOPhovk/com.apple.testmanagerd.unix-domain.socket"
        ));
        assert!(!would_allow(
            "network-outbound",
            "/private/tmp/com.apple.launchd.ku5xOPhovk/Listeners"
        ));
    }

    // SBPL is last-match-wins, so the carve-outs are worthless above the allow.
    #[test]
    fn denies_sockets_after_it_allows_them() {
        let sb = generate("/tmp/ws", "/Users/nobody", &[], &[], &[]);
        assert!(!sb.contains("(allow network*)"));
        let allow = sb.find("(allow network-outbound\n").expect("socket allow");
        let deny = sb.find("(deny network-outbound (regex").expect("launchd deny");
        assert!(allow < deny);
        let carve = sb
            .find("com\\.apple\\.testmanagerd\\.unix-domain\\.socket)$\"))")
            .expect("testmanagerd allow");
        assert!(deny < carve);
        assert!(sb.contains(
            "(deny file-read* file-read-metadata file-write* file-ioctl network-outbound\n"
        ));
    }

    #[test]
    fn allows_only_the_global_preference_domain() {
        assert!(would_allow(
            "user-preference-read",
            "kcfpreferencesanyapplication"
        ));
        assert!(would_allow("user-preference-read", "com.apple.dt.xcode"));
        assert!(!would_allow("user-preference-read", "com.apple.triald"));
        assert!(!would_allow("user-preference-write", "com.apple.dt.xcode"));
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
        assert!(would_allow("file-ioctl", "/dev/ptmx"));
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

        let sb = generate(&nested.to_string_lossy(), "/Users/nobody", &[], &[], &[]);
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

        let sb = generate(&ws.to_string_lossy(), "/Users/nobody", &[], &[], &[]);
        assert!(sb.contains(&format!("(subpath \"{}/main/.git\")", tmp.display())));
        assert!(sb.contains(&format!("(literal \"{}/.git\")", ws.display())));

        std::fs::remove_dir_all(&tmp).unwrap();
    }

    #[test]
    fn workspace_outside_any_repository_grants_nothing_extra() {
        let tmp = std::env::temp_dir().join(format!("aibox-profile-bare-{}", std::process::id()));
        std::fs::create_dir_all(&tmp).unwrap();
        let sb = generate(&tmp.to_string_lossy(), "/Users/nobody", &[], &[], &[]);
        assert!(!sb.contains(&format!("{}/.claude\")", tmp.display())));
        assert!(!sb.contains(&format!("{}/.git\")", tmp.display())));
        std::fs::remove_dir_all(&tmp).unwrap();
    }

    #[test]
    fn shell_startup_files_and_orca_hook_scripts_are_read_only_when_present() {
        let home = std::env::temp_dir().join(format!("aibox-profile-home-{}", std::process::id()));
        std::fs::create_dir_all(home.join(".orca/agent-hooks")).unwrap();
        std::fs::write(home.join(".zshenv"), "").unwrap();
        let sb = generate("/tmp/ws", &home.to_string_lossy(), &[], &[], &[]);
        assert!(sb.contains(&format!("(literal \"{}/.zshenv\")", home.display())));
        assert!(sb.contains(&format!(
            "(subpath \"{}/.orca/agent-hooks\")",
            home.display()
        )));
        std::fs::remove_dir_all(&home).unwrap();
    }

    // Everything beside the hook channel in Orca's userData directory -- its
    // cookies and their encryption key, the vault, the session authority key,
    // the agent account credentials -- was readable under an earlier grant of
    // the whole directory.
    #[test]
    fn grants_orcas_hook_channel_and_nothing_beside_it() {
        let home = std::env::temp_dir().join(format!("aibox-profile-orca-{}", std::process::id()));
        let orca = home.join("Library/Application Support/orca");
        std::fs::create_dir_all(orca.join("agent-hooks")).unwrap();
        std::fs::create_dir_all(orca.join("ai-vault")).unwrap();
        std::fs::write(orca.join("Cookies"), "").unwrap();

        let sb = generate("/tmp/ws", &home.to_string_lossy(), &[], &[], &[]);
        assert!(sb.contains(&format!("(subpath \"{}/agent-hooks\")", orca.display())));
        assert!(!sb.contains(&format!("(subpath \"{}\")", orca.display())));
        assert!(!sb.contains("ai-vault"));
        assert!(!sb.contains("Cookies"));
        std::fs::remove_dir_all(&home).unwrap();
    }

    #[test]
    fn allows_finder_staging_wherever_the_volume_puts_it() {
        assert!(would_allow(
            "file-write-create",
            "/Volumes/Backup/.TemporaryItems/folders.501/x"
        ));
        assert!(would_allow(
            "file-read-data",
            "/Users/eric/Code/.TemporaryItems/a"
        ));
        // A whole path segment, not a prefix of one.
        assert!(!would_allow("file-read-data", "/Users/eric/.TemporaryItemsX/a"));
        assert!(!would_allow("file-read-data", "/Users/eric/Code/a"));

        // The crown-jewel deny is emitted last and so still outranks it.
        let sb = generate("/tmp/ws", "/Users/nobody", &[], &[], &[]);
        let allow = sb.find(".TemporaryItems(/|$)").expect("staging allow");
        let deny = sb
            .find("(deny file-read* file-read-metadata")
            .expect("hard deny");
        assert!(allow < deny);
    }

    // Instruments' recording helper inherits the sandbox, and its kernel
    // tracing is all sysctl writes. The rule is scoped by name so the rest of
    // sysctl stays read-only, and the filter must agree with the profile or
    // an allowed write would still be logged as a denial.
    fn sb_has_bare_authorization_allow() -> bool {
        generate("/tmp/ws", "/Users/nobody", &[], &[], &[]).contains("(allow authorization-right-obtain)")
    }

    #[test]
    fn allows_only_the_kernel_tracing_sysctls() {
        assert!(would_allow("sysctl-write", "ktrace.background_pid"));
        assert!(would_allow("sysctl-write", "kperf.blessed_preempt"));
        assert!(would_allow("sysctl-write", "kern.kdebug"));
        assert!(would_allow("sysctl-write", "vm.self_region_info_flags"));
        assert!(would_allow("sysctl-write", "vm.get_owned_vmobjects"));
        assert!(!would_allow("sysctl-write", "vm.get_owned_vmobjectsx"));
        assert!(!would_allow("sysctl-write", "vm.page_size"));
        assert!(!would_allow("sysctl-write", "kern.hostname"));
        assert!(!would_allow("sysctl-write", "net.inet.ip.forwarding"));
        assert!(would_allow("authorization-right-obtain", "system.privilege.taskport"));
        assert!(!would_allow("authorization-right-obtain", "system.preferences"));
        assert!(!sb_has_bare_authorization_allow());

        let sb = generate("/tmp/ws", "/Users/nobody", &[], &[], &[]);
        assert!(sb.contains("(allow sysctl-write\n  (sysctl-name-prefix \"kern.kdebug\")"));
        assert!(!sb.contains("(allow sysctl-write)"));
        assert!(!sb.contains("(allow sysctl*)"));
    }

    #[test]
    fn emits_a_scoped_preference_rule() {
        let sb = generate("/tmp/ws", "/Users/nobody", &[], &[], &[]);
        assert!(sb.contains(
            "(allow user-preference-read (preference-domain \"kCFPreferencesAnyApplication\")\n  (preference-domain \"com.apple.CoreSimulator\")"
        ));
        assert!(!sb.contains("(allow user-preference-read)\n"));
        let _ = Path::new("/");
    }
}
