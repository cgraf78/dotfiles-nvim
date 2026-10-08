# VSCode-Style Keymaps

This directory backs the `config.keymaps.vscode` domain. The goal is not to
make Neovim pretend to be VSCode wholesale; it is to preserve the editing
muscle memory that matters most across terminal, tmux, and Neovim:

- Shift-arrow selection
- Ctrl/Cmd-style find, replace, copy, cut, paste, save, undo, and redo
- LSP aliases such as F2, F12, Shift-F12, and Ctrl-.
- predictable paste behavior that works with Yanky and terminal clipboards

## Design Rules

Keep the stateful selection mechanics in `selection.lua`. Other modules should
ask that module to build selection mappings instead of duplicating mode tables
or visual-mode edge cases.

Keep modules focused by user workflow:

- `find.lua` owns find prompt behavior.
- `replace.lua` owns local and workspace replace commands.
- `lsp.lua` owns VSCode-style LSP aliases.
- `paste.lua` owns paste-mode integration.
- `selection.lua` owns the shared selection helpers.

When a mapping must differ across normal, insert, visual, and select modes,
document the reason near the mapping. Most bugs in this area are mode-specific.
