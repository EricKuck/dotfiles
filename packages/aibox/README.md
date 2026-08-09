# aibox

A macOS Seatbelt sandbox host for AI coding harnesses. It reproduces the
containerized setup's **filesystem** allow-listing without a container and adds
**live** add/remove of the directories the agent can see. No network isolation.

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

Two processes straddle the sandbox boundary, joined by a socketpair:

```
aibox (CLI)
  └─ aibox-host broker        OUTSIDE the sandbox, long-lived
       │  issues extension tokens; serves ALLOW/DENY/LIST on a unix socket
       │  socketpair fd (inherited across sandbox-exec)
       └─ sandbox-exec -f <profile>  aibox-host launch --  <harness>
            └─ aibox-host launch      INSIDE the sandbox, root
                 │  consumes/releases tokens on the fd
                 └─ claude / pi        gains directories live
```

- **Static protections** are baked into the generated Seatbelt profile as
  `subpath`/`literal`/`regex` rules: the workspace is read-write; the agent
  config/cred dirs (`~/.claude`, `~/.claude.json`, `~/.pi`, `~/.codex`, opencode
  dirs), activity bridge, toolchain caches (`~/.cargo`, `~/.npm`, `~/.gradle`,
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
- **Dynamic directories** never appear in the profile. `aibox allow` has the
  broker *issue* a `com.apple.app-sandbox.read-write` extension token (outside
  the sandbox) and push it to the launcher, which *consumes* it. Because a
  consumed extension applies to the shared sandbox label, the already-running
  harness gains the directory with no restart. `deny` releases the handle.

### Security boundary

Token issuance happens only outside the sandbox, driven by an explicit `allow`
you run. Workspace state mirrors the canonical full workspace path beneath
`~/.aibox/state/` (for example, `/Users/me/Code/app` maps to
`~/.aibox/state/Users/me/Code/app`) and has mode `0700`. It holds the shared
grant manifest; each concurrent session has a fresh random control capability under
`sessions/<session-id>/`. Denials are logged machine-wide, not per session (see
below). The broker requires
that capability on every request. Its Unix socket is intentionally placed in a
short, ephemeral `TMPDIR` path to stay within the platform socket-path limit.
The generated profile hard-denies that state root, even
against dynamic extensions. This matters because the sandbox may connect to a
Unix-domain socket under the broad network rule: it cannot read the capability,
so it cannot ask the broker to widen itself.

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
- **Supacode:** the app is a peer process on the same machine rather than the
  far side of a container, so a session started from a Supacode terminal needs
  no bridge: `$SUPACODE_SOCKET_PATH` connects straight through and the presence
  hooks write their OSC sequences to the same pty. Two things do need help. The
  `supacode` CLI and the terminfo entry for `$TERM` live inside the app bundle,
  covered by the `/Applications` rule above. And the presence hooks resolve
  their own pid and tty with `ps`, which Seatbelt refuses to exec because
  Apple's `/bin/ps` is setuid root; the Nix build puts a non-setuid `ps` ahead
  of it on the session's PATH. Without that, presence still arrives but carries
  no pid, and the app cannot sweep the badge of an agent that died without
  signalling.
- **Keep awake:** harness sessions receive `AIBOX_ACTIVITY_FILE` under
  `~/.aibox/activity`. Existing agent hooks touch it during a turn; a host-side
  watcher maps it to `caffeinate -i` and clears the assertion when the turn or
  session ends. `aibox shell` does not start this watcher.
- **Fish shell:** `aibox shell` shares host `~/.config/fish` and
  `~/.local/share/fish` read-write, so prompts, plugins, universal variables,
  and history work normally. It sets `AIBOX_SHELL=1` for shell-specific prompt
  customization. This is a deliberate persistence exception for the explicit
  shell escape hatch. The `~/.cargo` toolchain/cache is read-write (registry
  caches, installed binaries) and `~/.rustup` is read-only; the credential and
  secret files within both are hard-denied.
- **Denial logging:** every session enables Seatbelt's `(debug deny)` mode, and
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
  (`mach*`, `network*`, `signal`, ...) or a read under a path it grants
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
| `src/*.rs` | the `aibox-host` native core (broker, launcher, profile gen, ctl, ffi) |
| `bin/aibox` | the CLI; `claude`/`pi` are symlinks to it |
| `default.nix` | Nix package (`buildRustPackage` + CLI + symlinks) |
| `test-e2e.sh` | proves live grant/revoke through the core |
| `test-cli.sh` | proves the same through the CLI |
| `test-worktree.sh` | proves linked-worktree Git access |
| `test-supacode.sh` | proves app-bundle read access and `/dev` listing |
| `test-keepawake.sh` | proves the activity-to-caffeinate bridge with a fake host tool |
| `test-shell.sh` | proves Fish persistence, read-only rustup access, and secret exclusion |
| `test-multisession.sh` | proves concurrent workspace sessions share live grants |
| `test-rm.sh` | proves stale-state removal and live-session protection |
| `tools/denials.sh` | one-shot command runner that reports current-profile denials |

## Status

The core and CLI are working and proven end to end (see the test scripts). Not
yet done: a **profile hardening pass** — the static read allow-list is a
first cut and may need widening for real Gradle/Android/node/gh toolchains; run
your actual builds under it and add the paths they genuinely need.
