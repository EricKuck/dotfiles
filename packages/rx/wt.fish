function __wt_branches
    git for-each-ref --format='%(refname:short)' refs/heads refs/remotes/origin 2>/dev/null |
        string replace -r '^origin/' '' | string match -v -r '^(HEAD|origin)$' | sort -u
end

function __wt_worktree_branches
    git worktree list --porcelain 2>/dev/null | string replace -f -r '^branch refs/heads/' '' | tail -n +2
end

function __wt_prs
    gh pr list --json number,title --jq '.[] | "\(.number)\t\(.title)"' 2>/dev/null
end

set -l cmds mk pr rm ls list

complete -c wt -f
complete -c wt -n "not __fish_seen_subcommand_from $cmds" -a mk -d 'Create a worktree and open its tab'
complete -c wt -n "not __fish_seen_subcommand_from $cmds" -a pr -d 'Check out a GitHub PR in a worktree'
complete -c wt -n "not __fish_seen_subcommand_from $cmds" -a rm -d 'Remove a worktree, its branch and tab'
complete -c wt -n "not __fish_seen_subcommand_from $cmds" -a ls -d 'List worktrees and their tabs'

complete -c wt -n '__fish_seen_subcommand_from mk' -a '(__wt_branches)'
complete -c wt -n '__fish_seen_subcommand_from pr; and test (count (commandline -opc)) -eq 2' -a '(__wt_prs)'
complete -c wt -n '__fish_seen_subcommand_from rm' -a '(__wt_worktree_branches)'
complete -c wt -n '__fish_seen_subcommand_from rm' -s f -l force -d 'Discard changes and delete unmerged branch'
complete -c wt -n '__fish_seen_subcommand_from rm' -s k -l keep-branch -d 'Keep the branch'
