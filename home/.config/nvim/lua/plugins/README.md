# Neovim plugin specs

This directory contains LazyVim specs for editor UI, navigation, workspace
management, colors, and basic Git indicators. Keep reusable policy in
`lua/config/` and expose plugin-local keys through the Lazy spec.

Higher overlays may add more `*.lua` specs to this merged directory. The
`dotfiles-dev` overlay uses that extension point for coding, LSP, debugger,
formatting, linting, and advanced Git functionality.
