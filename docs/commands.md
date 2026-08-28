# Neovim launcher

`home/.local/bin/nvim` asks the inherited Termnav adapter to reuse a suitable
pane, then starts the Shdeps-managed Neovim binary when no reusable pane exists.

`home/.local/bin/ripgrep-link-host` adapts ripgrep's argument-free hostname
hook to the inherited `termnav link-host` command. It stays with the editor
ripgrep fragment that selects it.
