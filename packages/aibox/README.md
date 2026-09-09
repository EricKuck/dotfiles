# aibox

A filesystem sandbox host for AI coding harnesses: **Seatbelt** on macOS,
**bubblewrap** on Linux. It reproduces the containerized setup's **filesystem**
allow-listing without a container and adds **live** add/remove of the
directories the agent can see. IP traffic is not isolated; **unix domain
sockets are**, because that is where the credential agents live.

```
claude [args...]     pi [args...]     # start that harness, sandboxed, in yolo mode

aibox allow <dir>    # make <dir> visible read-write to every running session
aibox deny  <dir>    # revoke a directory from every running session
aibox status [dir]   # workspace path, sessions, denial logs, and visible dirs
aibox list           # every workspace with state
aibox rm [dir|path]  # remove state for a stopped workspace
aibox shell          # a sandboxed interactive shell
```

## How it works

Two processes straddle the sandbox boundary, joined by a socketpair. The shape
is the same on both platforms; only what travels over the socketpair differs.

```
aibox (CLI)
  └─ aibox-host broker        OUTSIDE the sandbox, long-lived
       │  issues grants; serves ALLOW/DENY/LIST on a unix socket
       │  socketpair fd (inherited across the jail)
       └─ sandbox-exec -f <profile>      aibox-host launch -- <harness>   (macOS)
          bwrap <mount plan> --          aibox-host launch -- <harness>   (Linux)
            └─ aibox-host launch      INSIDE the sandbox
                 │  applies/releases grants pushed over the fd
                 └─ claude / pi        gains directories live
```

- **Static protections** are baked into the generated policy. On macOS that is
  a Seatbelt profile of `subpath`/`literal`/`regex` rules; on Linux it is a
  bubblewrap mount plan, where the allow-list is the set of binds and everything
  else is denied by never being mounted at all. Either way: the workspace is
  read-write; the agent config/cred dirs (`~/.claude`, `~/.claude.json`, `~/.pi`, `~/.codex`, opencode
  dirs), read-only Orca hook scripts (`~/.orca/agent-hooks`) and its hook
  channel (see below), activity bridge,
  toolchain caches (`~/.cargo`, `~/.npm`, `~/.gradle`,
  `~/.m2`), RTK app data (`~/Library/Application Support/rtk`), and Homebrew
  (`/opt/homebrew`) are read-write; the credential files inside the caches
  (`~/.cargo/credentials`, `~/.cargo/credentials.toml`,
  `~/.gradle/gradle.properties`, `~/.m2/settings.xml`,
  `~/.m2/settings-security.xml`) and `~/.npmrc` (where npm keeps its registry
  tokens) are hard-denied; system and toolchain paths (`/usr`, `/bin`, `/System`,
  `/Library`, `/nix`, `/run/current-system`, `/Applications`, `~/Applications`)
  are read-only. App bundles are a toolchain location on macOS, not just where
  apps sit -- `cc` reaches `libxcrun` inside Xcode's bundle, and a terminal that
  ships a CLI and a terminfo entry keeps both inside its own. Shell startup
  files (`~/.zshenv` and friends) are read-only, since every `sh -c` the harness
  runs sources them. **The enclosing repository's `.git` and `.claude` are
  read-write wherever they sit relative to the workspace** (see below), and
  everything else on disk is denied.

  The toolchain list is broader than that summary: the JVM chain (`~/.gradle`,
  `~/.m2`, `~/.java`, `~/.sdkman`, `~/.konan`), Android (`~/.android` with its
  AVDs and adb key, both SDK locations), Apple (`~/Library/Developer` --
  DerivedData, CoreSimulator, CoreDevice -- plus `~/Library/MobileDevice`,
  SwiftPM and CocoaPods), Python (`~/.pyenv`, pip/uv/poetry caches, the
  `--user` prefix), Node (npm/yarn/pnpm/bun/deno and their version managers),
  Rust, Go and the Ruby tools mobile work reaches through fastlane. These rules
  are emitted whether or not the directory exists, because `$HOME` itself is not
  writable: a toolchain that creates its cache on first run needs the rule to be
  there already.

  **Finder staging.** `.TemporaryItems` is allowed as a whole path segment
  wherever it appears (`(regex #"/\.TemporaryItems(/|$)")`), because the
  atomic-save APIs stage into one at the root of whatever volume the file lives
  on -- often not the workspace's. It reads broader than it is: Seatbelt matches
  the *resolved* path, so a symlink by that name cannot reach through it into a
  denied directory, and the hard-denies are emitted last, so nothing under
  `~/.ssh` or the state root is reachable through it either. What it does give
  up is the ability to create a `.TemporaryItems` directory in any location the
  user can write, and to read whatever other applications have staged in one.

  **Sockets.** Connecting to a unix domain socket on macOS is a `network-outbound`
  operation carrying the socket's path -- not a file operation -- so a blanket
  `(allow network*)` hands out every agent socket on the machine regardless of
  what the file rules say about the keys behind them. `SSH_AUTH_SOCK` is the
  clearest case: `~/.ssh` is hard-denied, but ssh-agent will sign with those
  keys for anyone who can reach it. IP traffic is still unrestricted -- the
  workspace is the unit of containment, not the machine -- and so are `bind` and
  `accept`, since creating a socket file is already a `file-write*`. Only
  connecting out is allow-listed: mDNSResponder (DNS), syslog, usbmuxd (physical
  iOS devices), the Nix daemon, the temp directories where local dev services
  and CoreSimulator listen, and the workspace itself. launchd's own per-user
  socket directories are carved back out of the temp allows, and the sensitive
  home paths are denied for `network-outbound` alongside their file rules, which
  covers Docker Desktop's daemon socket in `~/.docker` and gpg-agent's in
  `~/.gnupg`.

  Linux has no equivalent control -- a socket is reachable exactly when a mount
  carries it -- so the same result comes from the mount plan: `XDG_RUNTIME_DIR`
  is the sandbox's own tmpfs, `/run` and `/var/run` are never mounted (so the
  Docker and systemd sockets are simply absent), and the agent socket named by
  `SSH_AUTH_SOCK` is masked where a shared temp mount would otherwise reach it.
  On both platforms the launcher clears `SSH_AUTH_SOCK`, `SSH_AGENT_PID`,
  `GPG_AGENT_INFO` and a unix `DOCKER_HOST` from the harness environment, so a
  tool takes the ordinary "no agent" path instead of hanging on a socket it
  cannot open.

  **A grant covers sockets, not just files.** `aibox allow <dir>` makes the
  sockets inside it connectable as well as readable, which is the only sensible
  reading of the command on Linux -- a grant is a bind mount, and a bind carries
  a socket in like anything else -- so macOS names `network-outbound` alongside
  the file operations in its extension rule to match. Either way the carve-outs
  still outrank the grant: `~/.ssh` and the state root cannot be re-opened by
  allowing a parent. On Linux, where no rule can deny a path back out of a
  mount, the broker refuses such a grant outright instead.

  **The practical consequence:** `git push` over SSH does not work by default.
  The escape hatch is the ordinary one -- `aibox allow` the directory holding
  the agent socket (`dirname "$SSH_AUTH_SOCK"`), which is explicit, live, scoped
  to one session and revocable with `aibox deny`. Otherwise use HTTPS with a
  credential helper the policy allows, or push from outside.

  Linux keeps the same list with the paths that platform actually uses
  (`~/.local/share/...` and `~/.cache/...` for `~/Library/...`, `/etc` and
  `/lib` beside `/usr`, no Homebrew), and diverges in three ways worth knowing:

  * A secret that sits *inside* an allowed tree cannot be left out of it, so it
    is **masked** by a deeper mount: `/dev/null` over a file, an empty tmpfs
    over a directory. A secret nothing mounts needs no rule and deliberately
    does not get one -- bwrap would create the destination it was told to cover.
  * **`$HOME` is aibox's own directory** (`~/.aibox/home`), with the real config
    and cache directories mounted onto it. Tools write to `$HOME` constantly and
    they write *atomically*: claude persists `~/.claude.json` by renaming a
    sibling over it, and `rename(2)` onto a bind-mounted file fails with
    `EBUSY`. A real directory underneath makes those writes work and persist,
    at the cost of `~/.claude.json` diverging from the host's copy after it is
    seeded once. Everything the harness is meant to share -- `~/.claude`,
    `~/.cargo`, the rest -- is mounted from the real home and shared as usual.
  * The session runs in its **own PID namespace**. That is not optional: a
    private `/proc` requires one, and binding the host's would expose the
    environment of every process running as the same user. bwrap runs a reaping
    init as PID 1 there. `XDG_RUNTIME_DIR` is likewise the sandbox's own empty
    tmpfs rather than the host's, which holds live ssh-agent and keyring
    sockets.
- **Dynamic directories** never appear in the policy.

  On macOS, `aibox allow` has the broker *issue* a
  `com.apple.app-sandbox.read-write` extension token (outside the sandbox) and
  push it to the launcher, which *consumes* it. Because a consumed extension
  applies to the shared sandbox label, the already-running harness gains the
  directory with no restart. `deny` releases the handle.

  Linux has no such token, but it has mount propagation, which gives the same
  shape. The broker unshares a user and mount namespace of its own, so it can
  bind-mount without being root on the machine, and marks one directory in it
  -- the *grant carrier* -- `MS_SHARED` before the session starts. bwrap makes
  everything it inherits a slave and binds the carrier in, so the sandbox's copy
  stays in the broker's peer group: a bind the broker adds under the carrier
  appears inside the running sandbox immediately. The "token" is therefore the
  carrier path, and the launcher -- which holds `CAP_SYS_ADMIN` over its own
  mount namespace, a nested user namespace it creates before forking the
  harness -- binds it onto the real path. `deny` unmounts it, and removes the
  mount point if the grant created it, so a revoked path goes back to not
  existing rather than quietly resolving to an empty directory.

### Security boundary

Grants originate only outside the sandbox, driven by an explicit `allow` you
run: macOS issues the token there, and on Linux the broker's namespace -- not
the sandbox -- is the only place with a view of the whole filesystem. The
carrier holds nothing but directories that have already been granted, so the
second path they are reachable at inside the sandbox gives away nothing. Workspace state mirrors the canonical full workspace path beneath
`~/.aibox/state/` (for example, `/Users/me/Code/app` maps to
`~/.aibox/state/Users/me/Code/app`) and has mode `0700`. It holds the shared
grant manifest; each concurrent session has a fresh random control capability under
`sessions/<session-id>/`. Denials are logged machine-wide, not per session (see
below). The broker requires
that capability on every request. Its Unix socket is placed in `XDG_RUNTIME_DIR`
where there is one and `TMPDIR` otherwise -- an ephemeral path short enough for
the platform's socket-path limit. The generated profile hard-denies that state
root, even against dynamic extensions, so the sandbox cannot read the capability
and cannot ask the broker to widen itself. The endpoint itself is also put out
of reach: macOS denies `network-outbound` to it by name, and on Linux
`XDG_RUNTIME_DIR` is replaced by a tmpfs, so it is not merely unauthorized but
absent. Nothing inside needs it -- the launcher reaches the broker over the
inherited socketpair. A mount namespace has no rule that
denies a path back out of a mount, so the Linux side gets there differently: the
plan generator refuses to emit a plan in which any mount would carry the state
root in, and the broker refuses to grant a directory that contains it.

## Integrations

- **The enclosing repository:** the profile generator walks up from the
  workspace to the nearest directory holding a `.git`, and grants that root's
  `.git` and `.claude` read-write. A workspace nested inside a larger repository
  (say `~/.config/nix/packages/foo` in the `~/.config/nix` repo) resolves and
  updates its git metadata normally, and reads the project settings that live
  beside it. A linked worktree keeps `.git` as a file pointing into the main
  repository, so its common Git directory is read out and granted too.

  The rule grants only those two directories: the repository's own files and the
  parent directory's listing stay denied, so allowing the metadata never exposes
  a repo's working tree. It is scoped to the repository the workspace belongs
  to -- an earlier version matched `.git` by path component
  (`(regex #".*/\\.git(/.*)?$")`), which reached every checkout on the machine,
  including ones sitting inside otherwise-denied directories.
- **Orca:** the host app runs outside the sandbox; what runs inside is its agent
  hook (`~/.orca/agent-hooks/claude-hook.sh`), which POSTs each event to
  `http://127.0.0.1:<port>` and, when nothing is listening, appends to a spool
  beside the endpoint file. That needs one grant: its hook channel
  (`~/Library/Application Support/orca/agent-hooks`, `~/.config/orca/agent-hooks`
  on Linux), read-write for the spool. The rest of Orca's userData directory is
  **not** granted, and used to be: it holds the app's cookies and the Chromium
  key that decrypts them, its `ai-vault`, its session authority key, the agent
  account credentials it manages, and `orca-runtime.json`.

  That last file is why this matters beyond secrecy. It carries the auth token
  for Orca's runtime, which the `orca` CLI uses to create worktrees and run
  commands in panes -- and the CLI is on `PATH` inside the sandbox. The runtime
  advertises two transports: a unix socket beside the token, and a websocket on
  a TCP port. So the socket rules alone do **not** close this, because IP
  traffic is deliberately unrestricted; what closes it is not granting the
  directory the token sits in. A sandboxed agent that can read
  `orca-runtime.json` can drive the host app and run commands outside its own
  jail, whatever the network policy says.

  Neither the token nor the socket is granted by default now. The hooks do not
  need the CLI, and `aibox allow` on that directory can hand it over per session
  if you decide you want the agent driving Orca -- which is a deliberate escape
  hatch, not an oversight.

- **Keep awake:** harness sessions receive `AIBOX_ACTIVITY_FILE` under
  `~/.aibox/activity`. Existing agent hooks touch it during a turn; a host-side
  watcher maps it to `caffeinate -i` (macOS) or `systemd-inhibit --what=idle:sleep`
  (Linux) and clears the assertion when the turn or session ends. Neither tool
  is required: without one, the watcher does nothing. `aibox shell` does not
  start this watcher.
- **Fish shell:** `aibox shell` shares host `~/.config/fish` and
  `~/.local/share/fish` read-write, so prompts, plugins, universal variables,
  and history work normally. It sets `AIBOX_SHELL=1` for shell-specific prompt
  customization. This is a deliberate persistence exception for the explicit
  shell escape hatch. `~/.cargo` and `~/.rustup` are both read-write --
  rustup installs a toolchain into the latter whenever a repo's
  `rust-toolchain.toml` names one that is missing -- and the credential and
  secret files within both are hard-denied.
- **Denial logging (macOS only):** a bubblewrap sandbox denies by omission --
  an unmounted path is simply absent, and there is no violation stream to
  record -- so this whole mechanism is Seatbelt's. On macOS, every session
  enables Seatbelt's `(debug deny)` mode, and
  all sessions of all workspaces write one shared mode-`0600` SQLite database
  at `~/.aibox/state/denials.db` (override with `AIBOX_DENIAL_LOG`). It sits at
  the state root, which the profile hard-denies, so no sandboxed harness can
  read or rewrite its own history, and `aibox rm` of a workspace does not
  discard it. Denials arrive from the machine-wide unified log with no session
  identity attached, so brokers elect a single writer through `denials.lock`
  (one `log stream` per machine, not per session) and rows identify the
  denying process rather than a workspace. Another live session takes over the
  stream within a couple of seconds if the owning one exits. Rows include
  unredacted paths, so keep the database private and treat it as diagnostic
  data.

  Because that log is machine-wide, most of what arrives belongs to macOS's own
  sandboxed daemons rather than to a session. The broker drops any denial its
  own profile would have allowed -- an operation the profile grants outright
  (`mach*`, `signal`, `iokit*`, ...) or a read under a path it grants
  (`/System`, `/private/var/db`, `/private/tmp`, ...) provably came from some
  other sandbox. The test reads the same tables the profile is emitted from, so
  a rule cannot be allowed there and still be logged here. A short list of
  platform daemon names covers the stragglers that fall outside those static
  allows. Home-relative and workspace paths are never filtered: those denials
  are the point.

  Rows are aggregated at write time, one per `(process, operation, pattern,
  hour)`, so a noisy build collapses thousands of events into a handful of
  counting rows instead of a line each. `pattern` is the denied path with digit
  runs normalized to `\d+` and long hex runs (cache keys, git object ids) to
  `<hash>`; `count` bumps per event, `first_seen`/`example_path` record the
  first sighting, `last_seen`/`last_pid` the most recent. Only the newest 30
  days of hourly buckets are kept (the jsonl it replaced rotated at 32 MiB). A
  legacy `denials.jsonl` found beside the database (or a stale `AIBOX_DENIAL_LOG`
  still naming the old file) is imported and renamed aside on the first session
  after upgrading.

  ```sh
  # What is being denied, and how often
  sqlite3 ~/.aibox/state/denials.db \
    "SELECT process, operation, pattern, SUM(count), MAX(last_seen)
     FROM denials GROUP BY 1, 2, 3 ORDER BY 4 DESC LIMIT 30"

  # One process's recent events
  sqlite3 -separator $'\t' ~/.aibox/state/denials.db \
    "SELECT hour, operation, pattern, count FROM denials
     WHERE process = 'claude' ORDER BY last_seen DESC LIMIT 50"
  ```

## Layout

| Path | What |
|---|---|
| `src/broker.rs` | outside the sandbox: owns the session, serves the control socket |
| `src/launcher.rs` | inside the sandbox: applies grants, runs the harness |
| `src/profile.rs` | macOS: generates the Seatbelt profile |
| `src/sandbox.rs` | macOS: issues and consumes sandbox-extension tokens |
| `src/plan.rs` | Linux: generates the bubblewrap mount plan |
| `src/bwrap.rs` | Linux: namespaces, the grant carrier, and the binds it carries |
| `src/denials.rs` | macOS: the unified-log denial stream (`denials_off.rs` elsewhere) |
| `src/repo.rs`, `proto.rs`, `ctl.rs`, `ffi.rs`, `sqlite.rs` | shared plumbing |
| `bin/aibox` | the CLI; `claude`/`pi` are symlinks to it |
| `default.nix` | Nix package (`buildRustPackage` + CLI + symlinks) |
| `test-e2e.sh` | proves live grant/revoke through the core |
| `test-cli.sh` | proves the same through the CLI |
| `test-worktree.sh` | proves linked-worktree Git access |
| `test-keepawake.sh` | proves the activity-to-caffeinate bridge with a fake host tool |
| `test-shell.sh` | proves Fish persistence, rustup access, and secret exclusion |
| `test-socket-grant.sh` | proves a grant makes a unix socket connectable, not just visible |
| `test-multisession.sh` | proves concurrent workspace sessions share live grants |
| `test-rm.sh` | proves stale-state removal and live-session protection |
| `tools/denials.sh` | one-shot command runner that reports current-profile denials (macOS) |

## Status

**macOS** is working and proven end to end (see the test scripts).

**Linux** is new. It builds and its policy generation is unit-tested, but the
namespace and propagation machinery has not yet been exercised on a Linux
machine — the shell tests are the way to do that, in this order: `test-e2e.sh`
(live grant and revoke), `test-cli.sh`, `test-multisession.sh`, then
`test-shell.sh` and `test-git.sh`. It needs unprivileged user namespaces
enabled, which is also what rootless `bwrap` needs; where they are off, a
session still runs with its static mounts and `aibox allow` says it will take
effect next session instead.

The **socket policy is newly narrowed** and the **toolchain allow-list newly
widened** for the JVM/Android/Apple/Python/Node/Rust chains. Both are derived
rather than observed: the profile compiles and the rule ordering is unit-tested,
but no real Gradle, Xcode or npm build has yet run under them. macOS makes that
cheap to check — every miss lands in the denial log, so run your actual builds
and `tools/denials.sh` will name what got refused. Two shapes to expect: a
toolchain path nobody listed, and a unix socket that is now denied by default.

**Socket grants are unproven on macOS.** Whether the kernel honours a consumed
file extension for a `network-outbound` check is undocumented; the rule is
written and `test-socket-grant.sh` settles it. On Linux the same test should
pass structurally, since a grant is a bind. If macOS comes back negative, socket
grants there need a different mechanism — most likely the broker proxying the
socket to a path already inside the policy — and the test says so in its
verdict.
