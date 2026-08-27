# Neovim update hook

`home/.local/lib/dotfiles/merge-hooks.d/nvim.sh` updates Lazy-managed plugins
only when Neovim is installed, idle, and already initialized. Its lock is
owner-checked and safely reclaimed after interrupted updates.
