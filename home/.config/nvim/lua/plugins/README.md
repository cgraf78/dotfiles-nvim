# Neovim plugin specs

This directory contains LazyVim specs for editor UI, navigation, workspace
management, colors, and basic Git indicators. Keep reusable policy in
`lua/config/` and expose plugin-local keys through the Lazy spec.

Higher overlays may add ordinary `*.lua` specs to this merged directory. Specs
that must load before or after this namespace use the explicit
`lua/dotfiles/lazyvim_extras/`, `lua/dotfiles/plugin_overrides/`, and
`lua/dotfiles/final_policy/` extension points instead of depending on filenames
to control order.
