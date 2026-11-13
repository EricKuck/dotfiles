# Create or tear down git worktrees under ~/Code/worktrees, with a tab in the repo's Rex session.

usage() {
  cat >&2 <<'EOF'
usage: wt mk BRANCH [BASE]
       wt pr NUMBER [BRANCH]
       wt rm [-f|--force] [-k|--keep-branch] [PATH|BRANCH]
       wt ls

After mk or pr, an untracked .wt script in the main checkout runs in the new
worktree with WT_MAIN, WT_PATH and WT_BRANCH set. It runs with bash unless it
is executable, in which case its shebang decides.
EOF
  exit 2
}

repo_name() {
  local common repo
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir)
  case $(basename "$common") in
    .git | .bare) repo=$(dirname "$common") ;;
    *) repo=$common ;;
  esac
  basename "$repo" .git
}

main_worktree() {
  git -C "$1" worktree list --porcelain | awk '/^worktree /{print substr($0,10); exit}'
}

worktree_for_branch() {
  git worktree list --porcelain |
    awk -v b="branch refs/heads/$1" '/^worktree /{w=substr($0,10)} $0==b{print w}'
}

worktree_path() {
  echo "$HOME/Code/worktrees/$(repo_name .)/${1//\//-}"
}

default_branch() {
  local ref
  if ref=$(git -C "$1" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null); then
    ref=${ref#origin/}
    if git -C "$1" show-ref --verify --quiet "refs/heads/$ref"; then
      echo "$ref"
      return
    fi
  fi
  for ref in main master; do
    if git -C "$1" show-ref --verify --quiet "refs/heads/$ref"; then
      echo "$ref"
      return
    fi
  done
}

repo_session() {
  rex ls --json | jq -r --arg n "$1" 'first(.sessions[] | select(.label == $n) | .session_id) // empty'
}

run_setup() {
  local dest=$1 main script
  main=$(main_worktree "$dest")
  script=$main/.wt
  [ -f "$script" ] || return 0

  if git -C "$main" ls-files --error-unmatch .wt >/dev/null 2>&1; then
    echo "wt: not running $script because git tracks it; only an untracked .wt runs" >&2
    return 0
  fi

  if ! (
    cd "$dest"
    export WT_MAIN=$main WT_PATH=$dest
    WT_BRANCH=$(git branch --show-current)
    export WT_BRANCH
    if [ -x "$script" ]; then "$script"; else bash "$script"; fi
  ); then
    echo "wt: $script failed; the worktree is still set up" >&2
  fi
}

add() {
  [ $# -ge 1 ] || usage
  local branch=$1 base=${2:-HEAD} path
  path=$(worktree_path "$branch")

  if [ -e "$path" ]; then
    echo "wt: $path already exists" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$path")"

  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git worktree add "$path" "$branch"
  elif [ $# -lt 2 ] && git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    git worktree add --track -b "$branch" "$path" "origin/$branch"
  else
    git worktree add -b "$branch" "$path" "$base"
  fi

  run_setup "$path"
  rx "$path"
}

pr() {
  [ $# -ge 1 ] || usage
  local number=$1 branch=${2:-} path existing
  case $number in '' | *[!0-9]*) usage ;; esac
  if [ -z "$branch" ]; then
    branch=pr-$number-$(gh pr view "$number" --json headRefName --jq .headRefName)
  fi

  existing=$(worktree_for_branch "$branch")
  if [ -n "$existing" ]; then
    rx "$existing"
    return
  fi

  path=$(worktree_path "$branch")
  if [ -e "$path" ]; then
    echo "wt: $path already exists" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$path")"

  git worktree add --detach "$path" HEAD
  if ! (cd "$path" && gh pr checkout "$number" --branch "$branch"); then
    git worktree remove --force "$path"
    rmdir "$(dirname "$path")" 2>/dev/null || true
    exit 1
  fi

  run_setup "$path"
  rx "$path"
}

confirm() {
  local answer
  if [ ! -t 0 ]; then
    echo "wt: $1; pass -f to delete anyway${2:+ or $2}" >&2
    exit 1
  fi
  read -r -p "wt: $1. Continue? [y/N] " answer
  case $answer in
    y | Y | yes) ;;
    *) exit 1 ;;
  esac
}

remove() {
  local force='' keep='' target top name branch main default unmerged session='' window='' current=''
  while [ $# -gt 0 ]; do
    case $1 in
      -f | --force) force=1 ;;
      -k | --keep-branch) keep=1 ;;
      -fk | -kf) force=1 keep=1 ;;
      -*) usage ;;
      *) break ;;
    esac
    shift
  done
  target=${1:-.}

  if [ -d "$target" ]; then
    top=$(git -C "$target" rev-parse --show-toplevel)
  else
    top=$(worktree_for_branch "$target")
    if [ -z "$top" ]; then
      echo "wt: no worktree for branch $target" >&2
      exit 1
    fi
  fi

  if [ "$(git -C "$top" rev-parse --absolute-git-dir)" = \
    "$(git -C "$top" rev-parse --path-format=absolute --git-common-dir)" ]; then
    echo "wt: $top is the main worktree, not removing it" >&2
    exit 1
  fi

  name=$(repo_name "$top")
  branch=$(git -C "$top" branch --show-current)
  main=$(main_worktree "$top")
  default=$(default_branch "$top")

  if [ -n "$branch" ] && [ "$branch" = "$default" ] && [ -z "$keep" ]; then
    echo "wt: $branch is the default branch, keeping it" >&2
    keep=1
  fi

  if [ -z "$force" ]; then
    if [ -n "$(git -C "$top" status --porcelain)" ]; then
      echo "wt: $top has uncommitted changes; use wt rm -f to discard them" >&2
      exit 1
    fi
    if [ -z "$branch" ]; then
      unmerged=$(git -C "$top" rev-list --count HEAD --not --branches --remotes)
      [ "$unmerged" -eq 0 ] || confirm "detached HEAD has $unmerged commit(s) on no branch or remote"
    elif [ -z "$keep" ]; then
      unmerged=$(git -C "$top" rev-list --count "refs/heads/$branch" --not ${default:+"refs/heads/$default"} --remotes)
      [ "$unmerged" -eq 0 ] || confirm "$branch has $unmerged commit(s) not in ${default:+$default or }any remote" "-k to keep the branch"
    fi
  fi

  session=$(repo_session "$name") || session=
  if [ -n "$session" ]; then
    window=$(rex window ls -s "$session" --json |
      jq -r --arg t "${branch:-$(basename "$top")}" 'first(.windows[] | select(.label == $t) | .window_id) // empty') || window=
  fi

  cd "$main"
  if [ -n "$force" ]; then
    git worktree remove --force "$top"
  else
    git worktree remove "$top"
  fi
  rmdir "$(dirname "$top")" 2>/dev/null || true

  if [ -n "$branch" ] && [ -z "$keep" ]; then
    git branch -D "$branch"
  fi

  [ -n "$window" ] || return 0
  current=$(rex whoami --json | jq -r '.window_id // empty') || current=
  if [ "$window" = "$current" ]; then
    echo "wt: closing this tab"
    # Detached so this script can exit before its own tab goes away.
    (sleep 1 && rex window close -s "$session" "$window") </dev/null >/dev/null 2>&1 &
  else
    rex window close -s "$session" "$window"
  fi
}

list() {
  local name here session labels=''
  name=$(repo_name .)
  here=$(git rev-parse --show-toplevel 2>/dev/null) || here=
  session=$(repo_session "$name") || session=
  if [ -n "$session" ]; then
    labels=$(rex window ls -s "$session" --json | jq -r '.windows[].label') || labels=
  fi

  git worktree list --porcelain |
    awk -v here="$here" -v home="$HOME" -v labels="$labels" '
      BEGIN {
        n = split(labels, l, "\n")
        for (i = 1; i <= n; i++) if (l[i] != "") tab[l[i]] = 1
        rows = 0; wa = 8; wb = 3
      }
      function flush(  label, shown) {
        if (path == "") return
        label = branch != "" ? branch : base(path)
        shown = branch != "" ? branch : "(detached)"
        row((path == here ? "* " : "  ") shown, label in tab ? "open" : "-", path)
        used[label] = 1
        path = ""; branch = ""
      }
      function base(p) { sub(/.*\//, "", p); return p }
      function row(a, b, c) {
        rows++; A[rows] = a; B[rows] = b; C[rows] = c
        if (length(a) > wa) wa = length(a)
        if (length(b) > wb) wb = length(b)
      }
      /^worktree / { flush(); path = substr($0, 10) }
      /^branch / { branch = substr($0, 19) }
      END {
        flush()
        for (t in tab) if (!(t in used)) row("  " t, "open", "(no worktree)")
        printf "%-" wa "s  %-" wb "s  %s\n", "  BRANCH", "TAB", "PATH"
        for (i = 1; i <= rows; i++) {
          p = C[i]
          if (index(p, home "/") == 1) p = "~" substr(p, length(home) + 1)
          printf "%-" wa "s  %-" wb "s  %s\n", A[i], B[i], p
        }
      }'
}

case ${1:-} in
  mk) shift; add "$@" ;;
  pr) shift; pr "$@" ;;
  rm) shift; remove "$@" ;;
  ls | list) shift; list "$@" ;;
  *) usage ;;
esac
