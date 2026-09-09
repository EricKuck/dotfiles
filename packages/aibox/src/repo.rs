// The enclosing repository of a workspace. Both sandbox backends grant its
// .git and .claude -- a workspace nested below the repo root resolves both
// above its own subtree -- so the resolution lives apart from either policy
// generator.

use std::path::{Path, PathBuf};

// Directories an enclosing repository shares with the workspace. Granting them
// by name leaves the rest of the repository denied -- its files, its listing,
// and any sibling secret.
pub const SHARED: &[&str] = &[".git", ".claude"];

// The nearest ancestor of the workspace holding a .git, the workspace itself
// included. None when the workspace is not inside a repository at all.
pub fn root(workspace: &str) -> Option<PathBuf> {
    let mut dir = Some(Path::new(workspace));
    while let Some(d) = dir {
        if d.join(".git").exists() {
            return Some(d.to_path_buf());
        }
        dir = d.parent();
    }
    None
}

// The main repository's .git, read out of a linked worktree's .git file. A
// linked worktree keeps .git as a FILE holding
// `gitdir: <main>/.git/worktrees/<name>`, and every command there reaches into
// the main repository's .git, which is nowhere near the workspace.
pub fn worktree_common_git(git: &Path) -> Option<PathBuf> {
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
