# Personal fish prompt. Inspiration for Async git operation taken from https://github.com/mattgreen/lucid.fish

# Rose Pine Moon
# set -g __prompt_color_fg e0def4
# set -g __prompt_color_section_1 eb6f92
# set -g __prompt_color_section_2 3e8fb0
# set -g __prompt_color_section_3 f6c177
# set -g __prompt_color_section_4 9ccfd8
# set -g __prompt_color_section_5 c4a7e7
# set -g __prompt_color_section_6 56526e
# set -g __prompt_color_success 4caf50
# set -g __prompt_color_error d32f2f
# set -g __prompt_arrow_color_success e0def4

# Snazzy
# set -g __prompt_color_fg fbf1c7
# set -g __prompt_color_section_1 d65d0e
# set -g __prompt_color_section_2 d79921
# set -g __prompt_color_section_3 689d6a
# set -g __prompt_color_section_4 458588
# set -g __prompt_color_section_5 665c54
# set -g __prompt_color_section_6 3c3836
# set -g __prompt_color_success 689d6a
# set -g __prompt_color_error cc241d
# set -g __prompt_arrow_color_success fbf1c7

# Frappe
set -g __prompt_color_fg 303446
set -g __prompt_color_text c6d0f5
set -g __prompt_color_section_1 ea999c
set -g __prompt_color_section_2 e5c890
set -g __prompt_color_section_3 a6d189
set -g __prompt_color_section_4 81c8be
set -g __prompt_color_section_5 8caaee
set -g __prompt_color_section_6 babbf1
set -g __prompt_color_success a6d189
set -g __prompt_color_error e78284
set -g __prompt_arrow_color_success a6d189

# One Dark
# set -g __prompt_color_fg cccccc
# set -g __prompt_color_text cccccc
# set -g __prompt_color_section_1 be5046
# set -g __prompt_color_section_2 d19a66
# set -g __prompt_color_section_3 98c379
# set -g __prompt_color_section_4 61afef
# set -g __prompt_color_section_5 979eab
# set -g __prompt_color_section_6 393e48
# set -g __prompt_color_success 98c379
# set -g __prompt_color_error be5046
# set -g __prompt_arrow_color_success cccccc

set -g __prompt_sections 'host|pwd|git|||time'
set -g __prompt_right_sections status-runtime

set -g __prompt_colors \
    $__prompt_color_section_1 \
    $__prompt_color_section_2 \
    $__prompt_color_section_3 \
    $__prompt_color_section_4 \
    $__prompt_color_section_5 \
    $__prompt_color_section_6

set -g __prompt_right_colors \
    $__prompt_color_section_5

set -g __prompt_symbol_macos \Ue711
set -g __prompt_symbol_linux \Ue712
set -g __prompt_symbol_nixos \Uf1105

set -g __prompt_runtime_format '%b %d %I:%M%p'

set -g __prompt_last_status 0
set -g __prompt_cmd_duration_str 0ms

set -g __prompt_dirty_indicator '•'
set -g __prompt_clean_indicator '✓'
set -g __prompt_git_symbol \uF418
set -g __prompt_error_symbol \uf530

# State used for memoization and async calls.
set -g __prompt_cmd_id 0
set -g __prompt_git_state_cmd_id -1
set -g __prompt_git_static ''
set -g __prompt_dirty ''

if date --date='@0' '+%s' >/dev/null 2>/dev/null
    # gnu
    function fish_command_timer_print_time
        date --date="@$argv[1]" +"$__prompt_runtime_format"
    end
else if date -r 0 '+%s' >/dev/null 2>/dev/null
    # bsd
    function fish_command_timer_print_time
        date -r "$argv[1]" +"$__prompt_runtime_format"
    end
end

function __prompt_cmd_postexec -e fish_postexec
    set -f cmd_pipestatus $pipestatus
    set -f cmd_duration $CMD_DURATION

    set -f SEC 1000
    set -f MIN 60000
    set -f HOUR 3600000

    set -f num_hours (math -s0 "$cmd_duration / $HOUR")
    set -f num_mins (math -s0 "$cmd_duration % $HOUR / $MIN")
    set -f num_secs (math -s0 "$cmd_duration % $MIN / $SEC")
    set -f num_millis (math -s0 "$cmd_duration % $SEC")
    set -f __prompt_cmd_duration_str ""
    if test $num_hours -gt 0
        set -f __prompt_cmd_duration_str {$__prompt_cmd_duration_str}{$num_hours}"h "
    end
    if test $num_mins -gt 0
        set -f __prompt_cmd_duration_str {$__prompt_cmd_duration_str}{$num_mins}"m "
    end
    if test $num_secs -gt 0
        set -f __prompt_cmd_duration_str {$__prompt_cmd_duration_str}{$num_secs}"s "
    end
    set -g __prompt_cmd_duration_str {$__prompt_cmd_duration_str}{$num_millis}"ms"

    set -g status_str ''
    set -g __prompt_last_status 0
    for status_code in $cmd_pipestatus
        if test "$status_code" -ne 0
            set -g __prompt_last_status $status_code

            switch $status_code
                case 1
                    set -f signal "ERROR [$status_code]"
                case 2
                    set -f signal "USAGE [$status_code]"
                case 64
                    set -f signal "USAGE [$status_code]"
                case 65
                    set -f signal DATAERR
                case 66
                    set -f signal NOINPUT
                case 67
                    set -f signal NOUSER
                case 68
                    set -f signal NOHOST
                case 69
                    set -f signal UNAVAILABLE
                case 70
                    set -f signal SOFTWARE
                case 71
                    set -f signal OSERR
                case 72
                    set -f signal OSFILE
                case 73
                    set -f signal CANTCREAT
                case 74
                    set -f signal IOERR
                case 75
                    set -f signal TEMPFAIL
                case 76
                    set -f signal PROTOCOL
                case 77
                    set -f signal NOPERM
                case 78
                    set -f signal CONFIG
                case 126
                    set -f signal NOPERM
                case 127
                    set -f signal NOTFOUND
                case "*"
                    set -f signal (fish_status_to_signal $status_code)
            end
            set -g status_str "$__prompt_error_symbol $signal"
            break
        end
    end
end

# Increment a counter each time a prompt is about to be displayed.
# Enables us to distingish between redraw requests and new prompts.
function __prompt_increment_cmd_id --on-event fish_prompt
    set __prompt_cmd_id (math $__prompt_cmd_id + 1)
end

# Abort an in-flight dirty check, if any.
function __prompt_abort_check
    if set -q __prompt_check_pid
        set -l pid $__prompt_check_pid
        functions -e __prompt_on_finish_$pid
        command kill $pid >/dev/null 2>&1
        set -e __prompt_check_pid
    end
end

function __prompt_git_status
    set -l prev_dirty $__prompt_dirty
    if test $__prompt_cmd_id -ne $__prompt_git_state_cmd_id
        __prompt_abort_check

        set __prompt_git_state_cmd_id $__prompt_cmd_id
        set __prompt_git_static ''
        set __prompt_dirty ''
    end

    set -l git_dir (git --no-optional-locks rev-parse --absolute-git-dir 2>/dev/null)
    if test -z "$git_dir"
        return
    end

    set -l branch (command git --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
    if test $status -ne 0
        set branch (command git --no-optional-locks rev-parse --short HEAD 2>/dev/null)
        if test $status -eq 0
            set branch (string sub --length 7 $branch)
            set branch "@$branch (detached)"
        end
    end

    if test -z $__prompt_git_static
        set -l action ""
        if test -f "$git_dir/MERGE_HEAD"
            set action merge
        else if test -f "$git_dir/CHERRY_PICK_HEAD"
            set action cherrypick
        else if test -f "$git_dir/REVERT_HEAD"
            set action revert
        else if test -f "$git_dir/BISECT_LOG"
            set action bisect
        else if test -d "$git_dir/rebase-merge"
            set action rebase
        else if test -d "$git_dir/rebase-apply"
            set action rebase
        end

        set -l state $branch
        if test -n $action
            set state "$state <$action>"
        end

        set -g __prompt_git_static "$__prompt_git_symbol $state"
    end

    # Fetch dirty status asynchronously.
    if test -z $__prompt_dirty
        if ! set -q __prompt_check_pid
            # Compose shell command to run in background
            set -l check_cmd "git --no-optional-locks status --porcelain --ignore-submodules 2>/dev/null | head -n1 | count"
            set -l cmd "if test ($check_cmd) != 0; exit 1; else; exit 0; end"

            begin
                # Defer execution of event handlers by fish for the remainder of lexical scope.
                # This is to prevent a race between the child process exiting before we can get set up.
                block -l

                set -g __prompt_check_pid 0
                command fish --private --command "$cmd" >/dev/null 2>&1 &
                set -l pid (jobs --last --pid)

                set -g __prompt_check_pid $pid

                # Use exit code to convey dirty status to parent process.
                function __prompt_on_finish_$pid --inherit-variable pid --on-process-exit $pid
                    functions -e __prompt_on_finish_$pid

                    if set -q __prompt_check_pid
                        if test $pid -eq $__prompt_check_pid
                            switch $argv[3]
                                case 0
                                    set -g __prompt_dirty_state 0
                                    if status is-interactive
                                        commandline -f repaint
                                    end
                                case 1
                                    set -g __prompt_dirty_state 1
                                    if status is-interactive
                                        commandline -f repaint
                                    end
                                case '*'
                                    set -g __prompt_dirty_state 2
                                    if status is-interactive
                                        commandline -f repaint
                                    end
                            end
                        end
                    end
                end
            end
        end

        if set -q __prompt_dirty_state
            switch $__prompt_dirty_state
                case 0
                    set -g __prompt_dirty $__prompt_clean_indicator
                case 1
                    set -g __prompt_dirty $__prompt_dirty_indicator
                case 2
                    set -g __prompt_dirty " <err >"
            end

            set -e __prompt_check_pid
            set -e __prompt_dirty_state
        end
    end

    # Render git status. When in-progress, use previous state to reduce flicker.
    echo -n $__prompt_git_static ''

    if ! test -z $__prompt_dirty
        echo -n $__prompt_dirty
    else if ! test -z $prev_dirty
        set_color --dim
        echo -n $prev_dirty
    end
end

function __prompt_print_prompt --description "prints an entire prompt given <sections> and <colors>"
    set -l section_index 0
    set -l split_sections (string split '|' $argv[1])
    set -l split_sections_count (count $split_sections)
    set -l colors $argv[2..-1]

    set -l output ''
    for section in $split_sections
        set section_index (math $section_index + 1)
        set -g __prompt_previous_section_color $__prompt_section_color
        set -g __prompt_section_color $colors[$section_index]

        set -l section_output ''

        set -l item_index 0
        set -l split_items (string split '-' $section)
        set -l split_items_count (count $split_items)
        set -l has_section_text false

        for item in $split_items
            set item_index (math $item_index + 1)
            set -l item_output ''
            switch $item
                case host
                    set item_output (__prompt_print_host)
                case pwd
                    set item_output (__prompt_print_pwd)
                case git
                    set item_output (__prompt_print_git)
                case time
                    set item_output (__prompt_print_time)
                case status
                    set item_output (__prompt_print_status)
                case runtime
                    set item_output (__prompt_print_runtime)
            end

            if test -n "$item_output"
                if $has_section_text
                    set item_output " $item_output"
                end

                set section_output $section_output $item_output
                set has_section_text true
            end
        end

        if test $section_index -eq 1
            set section_output "$(__prompt_print_opening_semicircle)" $section_output
        else
            if $has_section_text
                set section_output " " $section_output
            end
            set section_output "$(__prompt_begin_section)" $section_output
        end

        if test $split_sections_count -eq $section_index
            set section_output $section_output "$(__prompt_print_closing_semicircle)"
        else if $has_section_text
            set section_output $section_output " "
        end

        for section in $section_output
            set output "$output$(set_color $__prompt_color_fg)$(set_color -b $__prompt_section_color)$section"
        end
    end

    echo -n $output
end

function __prompt_print_opening_semicircle --description "prints the opening semicircle"
    set_color normal
    set_color $__prompt_section_color
    printf '\uE0B6'
end

function __prompt_print_closing_semicircle
    set_color normal
    set_color $__prompt_section_color
    printf '\uE0B4'
end

function __prompt_begin_section --description "prints the dividing arrow"
    set_color normal
    set_color $__prompt_previous_section_color
    set_color -b $__prompt_section_color
    printf '\uE0B0'
    set_color $__prompt_color_fg
end

function __prompt_print_host
    switch (uname -a)
        case "*Darwin*"
            printf "$__prompt_symbol_macos"
        case "*NixOS*"
            printf "$__prompt_symbol_nixos"
        case '*'
            printf "$__prompt_symbol_linux"
    end

    echo -n " $hostname"
end

function __prompt_print_pwd
    set -l dir (pwd | string replace "$HOME" '~')
    set -l parts (string split '/' $dir)
    set -l shortened_path false

    while test (string length $dir) -gt 25; and test (count $parts) -gt 2
        set shortened_path true
        set dir (string join '/' $parts[2..-1])
        set parts (string split '/' $dir)
    end

    if $shortened_path
        set dir '…/'$dir
    end

    echo -sn $dir
end

function __prompt_print_git
    set -l git_state (__prompt_git_status)
    if test $status -eq 0
        echo -sn $git_state
    end
end

function __prompt_print_time
    set -l time (string lower (date +"%-I:%M%p"))
    printf "\uF43A $time"
end

function __prompt_print_status
    if test (string length "$status_str") -ne 0
        set -g __prompt_section_color $__prompt_color_error
        set_color --bold $__prompt_color_fg
        echo -n "$status_str"
        set_color normal
        set_color $__prompt_color_fg
    else
        set -g __prompt_section_color $__prompt_color_success
    end
end

function __prompt_print_runtime
    echo -n $__prompt_cmd_duration_str
end

function __prompt_get_padding
    set -l space ''
    for i in (seq 1 $argv[1])
        set space ' '$space
    end
    printf $space
end

function __prompt_visual_length
    printf $argv | perl -pe 's/\x1b.*?[mGKH]//g' | wc -m
end

# Override vi mode prompt to nothing, don't use it
function fish_mode_prompt
end

# We fake the right prompt because the native one's vertical alignment is off
function fish_right_prompt
end

function fish_prompt
    echo ""

    set -l left_prompt (__prompt_print_prompt $__prompt_sections $__prompt_colors)
    set -l right_prompt (__prompt_print_prompt $__prompt_right_sections $__prompt_right_colors)
    set -l prompt_length (__prompt_visual_length "$left_prompt$right_prompt")
    set -l padding (math "$COLUMNS - $prompt_length")
    echo -n $left_prompt
    printf "%-"$padding"s" " "
    echo -n $right_prompt

    if test "$__prompt_last_status" -ne 0
        set_color $__prompt_color_error
    else
        set_color $__prompt_arrow_color_success
    end

    printf '\n\uF432 '
    set_color normal
end
