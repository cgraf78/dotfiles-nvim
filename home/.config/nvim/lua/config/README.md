# Neovim config modules

`lua/config/` holds editor-owned policy and small helper APIs consumed by
plugin specs. Reusable integrations stay behind dependency-owned interfaces;
for example, `termnav.lua`, `remote-open.lua`, `nvim-workspace.lua`, and
`dot-runtime.lua` adapt those providers without copying their implementation.
`session.lua` holds the environment checks shared by `remote-open.lua` and
`clipboard.lua`: whether an overlay declared the host remote, and whether the
terminal is VS Code's.

LazyVim loads `options.lua`, `autocmds.lua`, and `keymaps.lua` by convention.
Keep this lower-profile directory independent of LSP, Mason, debugger,
formatter, and linter policy. `dotfiles-dev` contributes those modules when the
`dev` profile is selected.
