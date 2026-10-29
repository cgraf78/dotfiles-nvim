# Neovim launcher

`home/.local/bin/nvim` asks the inherited Termnav adapter to reuse a suitable
pane, then starts the Shdeps-managed Neovim binary when no reusable pane exists.

`home/.local/bin/ripgrep-link-host` adapts ripgrep's argument-free hostname
hook to the inherited `termnav link-host` command. It stays with the editor
ripgrep fragment that selects it.

Ripgrep emits `nvim-remote://host/path:line:column` diagnostic links. Termnav
routes a local host back to the local editor and retains a remote host for
authenticated remote opening. Keeping this scheme distinct from literal
`file://` targets preserves filenames such as `report:2026` while still
passing search-result coordinates to Neovim.
