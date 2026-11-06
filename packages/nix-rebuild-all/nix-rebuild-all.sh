#!/usr/bin/env bash
if [ $# -gt 0 ]; then
  hosts=("$@")
else
  hosts=(IRLBuild KuckyNas KuckyThings)
fi

rebuild_script=$(cat "$REMOTE_SCRIPT")

notify() {
  /usr/bin/osascript -e "display notification \"$1\" with title \"nix rebuild\"" >/dev/null 2>&1 || true
}

declare -A session block blocked misses
running=()
failed=()

for host in "${hosts[@]}"; do
  label="rebuild-$host"

  if ! sessions=$(rex -S "$host" ls --json 2>&1); then
    echo "$host: unreachable: $sessions"
    failed+=("$host")
    continue
  fi

  # Sessions left open by a failed run would otherwise pile up.
  jq -r --arg label "$label" '.sessions[] | select(.label == $label) | .session_id' <<<"$sessions" |
    while read -r stale; do rex -S "$host" kill "$stale" >/dev/null; done

  if ! created=$(rex -S "$host" new "$label" --window "$host" --keep-open --json -- \
    sh -c "$rebuild_script" nix-rebuild 2>&1); then
    echo "$host: could not create session: $created"
    failed+=("$host")
    continue
  fi

  session[$host]=$(jq -r '.session_id' <<<"$created")
  block[$host]=$(jq -r '.initial_windows[0].block_ids[0]' <<<"$created")
  blocked[$host]=0
  misses[$host]=0
  running+=("$host")
  echo "$host: started"
done

# Remote servers can't push events to this script, so poll them.
while [ ${#running[@]} -gt 0 ]; do
  sleep 1
  still_running=()

  for host in "${running[@]}"; do
    target=(-S "$host" -s "${session[$host]}" -b "${block[$host]}")

    if ! process=$(rex "${target[@]}" block call process 2>&1); then
      misses[$host]=$((misses[$host] + 1))
      if [ "${misses[$host]}" -ge 10 ]; then
        echo "$host: lost track of the session: $process"
        failed+=("$host")
      else
        still_running+=("$host")
      fi
      continue
    fi
    misses[$host]=0

    exit_code=$(jq -r '.last_exit.exit_code // empty' <<<"$process")
    if [ -z "$exit_code" ]; then
      now_blocked=$(rex "${target[@]}" block call program_status 2>/dev/null |
        jq -r 'if any(.records[]?; .state == "blocked") then 1 else 0 end' || echo 0)
      if [ "$now_blocked" = 1 ] && [ "${blocked[$host]}" = 0 ]; then
        echo "$host: waiting for your password"
        notify "$host needs your sudo password"
      fi
      blocked[$host]=$now_blocked
      still_running+=("$host")
    elif [ "$exit_code" = 0 ]; then
      echo "$host: done"
      rex -S "$host" kill "${session[$host]}" >/dev/null
    else
      echo "$host: failed, session rebuild-$host left open on $host"
      notify "$host rebuild failed"
      failed+=("$host")
    fi
  done

  running=("${still_running[@]}")
done

if [ ${#failed[@]} -gt 0 ]; then
  echo "failed: ${failed[*]}"
  exit 1
fi
notify "All machines rebuilt"
