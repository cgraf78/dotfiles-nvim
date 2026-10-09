# Neovim plugin specs

This directory contains LazyVim specs for editor UI, navigation, workspace
management, colors, and basic Git indicators. Keep reusable policy in
`lua/config/` and expose plugin-local keys through the Lazy spec.

Higher overlays may add ordinary `*.lua` specs to this merged directory. Specs
that must load before or after this namespace use the explicit
`lua/dotfiles/lazyvim_extras/`, `lua/dotfiles/plugin_overrides/`, and
`lua/dotfiles/final_policy/` extension points instead of depending on filenames
to control order.

A key claimed by two plugin specs maps to whichever plugin lazy.nvim loads
last, so the overlay that owns the winning binding drops the other spec's key
with lazy.nvim's `{ lhs, false }` form in an `optional = true` fragment.
`nvim-test` fails on any shared claim and on any described global mapping that
loading a plugin changes, for whichever overlays are composed. Buffer-local
keys a plugin sets later (for example in an LSP `on_attach`) are not covered.

lazy.nvim merges `opts`, `keys`, `cmd`, `event`, `ft`, and `dependencies`
across specs for one plugin, but `init`, `config`, and `build` are last wins.
A higher overlay extends a plugin through an `opts` function and never sets
one of those hooks for a plugin that this overlay or LazyVim already sets, or
it silently replaces that hook. `nvim-test` fails when two specs set one.
