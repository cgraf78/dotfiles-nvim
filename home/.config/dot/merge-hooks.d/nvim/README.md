# Neovim Merge Hook

The `nvim` merge hook updates Lazy-managed plugins as part of every `dot
update`, after Shdeps has converged the Neovim runtime. It uses headless
Neovim, so it never adds network or update work to interactive startup.

The hook skips a host without `~/.config/nvim/init.lua`, an installed Lazy
runtime, a usable `nvim` command, or `pgrep` for safe process inspection. It
also skips while a Neovim process is active. When it runs, an atomic lock next
to Lazy's shared data tree makes new interactive Neovim processes wait before
loading Lazy, preventing a check-then-act race even when their XDG state homes
differ. A later `dot update` reclaims a lock only after atomically claiming its
owner record and confirming the recorded process identity has exited; otherwise
the next run retries after the editor exits or another updater releases the
lock.

The executable implementation lives at
`~/.local/lib/dotfiles/merge-hooks.d/nvim.sh`.
