# Open a directory in the Rex session named after its git repo; worktrees share the main repo's session.
# Usage: rx [DIR]

dir=$(cd "${1:-.}" && pwd -P)

if common=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
  top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || echo "$dir")
  case $(basename "$common") in
    .git | .bare) repo=$(dirname "$common") ;;
    *) repo=$common ;;
  esac
  name=$(basename "$repo" .git)
  tab=$(git -C "$dir" branch --show-current 2>/dev/null || true)
  [ -n "$tab" ] || tab=$(basename "$top")
else
  top=$dir
  name=$(basename "$dir")
  tab=$name
fi

session=$(rex ls --json | jq -r --arg n "$name" 'first(.sessions[] | select(.label == $n) | .session_id) // empty')

if [ -z "$session" ]; then
  session=$(rex new "$name" -c "$top" --window "$tab" --json | jq -r '.session_id')
  window=
else
  window=$(rex window ls -s "$session" --json |
    jq -r --arg t "$tab" 'first(.windows[] | select(.label == $t) | .window_id) // empty')
  if [ -z "$window" ]; then
    window=$(rex window new -s "$session" "$tab" -c "$top" --json | jq -r '.window_id')
  else
    rex focus -s "$session" "$window" >/dev/null
  fi
fi

if [ -n "$window" ]; then
  rex "do" session.select session_id="$session" window_id="$window" >/dev/null 2>&1 || true
else
  rex "do" session.select session_id="$session" >/dev/null 2>&1 || true
fi
