# Create or tear down git worktrees under ~/Code/worktrees, with a tab in the repo's Rex session.
# Usage: wt mk BRANCH [BASE]
#        wt rm [-f] [PATH|BRANCH]

usage() {
  echo "usage: wt mk BRANCH [BASE]" >&2
  echo "       wt rm [-f] [PATH|BRANCH]" >&2
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

add() {
  [ $# -ge 1 ] || usage
  local branch=$1 base=${2:-HEAD} name path
  name=$(repo_name .)
  path=$HOME/Code/worktrees/$name/${branch//\//-}

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

  rx "$path"
}

remove() {
  local force='' target top name branch main session window
  if [ "${1:-}" = -f ] || [ "${1:-}" = --force ]; then
    force=1
    shift
  fi
  target=${1:-.}

  if [ -d "$target" ]; then
    top=$(git -C "$target" rev-parse --show-toplevel)
  else
    top=$(git worktree list --porcelain |
      awk -v b="branch refs/heads/$target" '/^worktree /{w=substr($0,10)} $0==b{print w}')
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
  main=$(git -C "$top" worktree list --porcelain | awk '/^worktree /{print substr($0,10); exit}')
  cd "$main"

  if [ -n "$force" ]; then
    git worktree remove --force "$top"
  else
    git worktree remove "$top"
  fi
  rmdir "$(dirname "$top")" 2>/dev/null || true

  if [ -n "$branch" ]; then
    if [ -n "$force" ]; then
      git branch -D "$branch"
    elif ! git branch -d "$branch"; then
      echo "wt: kept branch $branch; use wt rm -f to delete it" >&2
    fi
  fi

  # Last, because this may be the tab running this script.
  session=$(rex ls --json | jq -r --arg n "$name" 'first(.sessions[] | select(.label == $n) | .session_id) // empty')
  [ -n "$session" ] || return 0
  window=$(rex window ls -s "$session" --json |
    jq -r --arg t "${branch:-$(basename "$top")}" 'first(.windows[] | select(.label == $t) | .window_id) // empty')
  [ -n "$window" ] || return 0
  rex window close -s "$session" "$window"
}

case ${1:-} in
  mk) shift; add "$@" ;;
  rm) shift; remove "$@" ;;
  *) usage ;;
esac
