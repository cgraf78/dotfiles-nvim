# Neovim Keymap Modules

This directory contains keymap domains that need more structure than the global
`keymaps.lua` entry point.

## Placement

- Put simple always-on mappings in `../keymaps.lua`.
- Put integration mappings here when setup timing, helper functions, or
  domain-specific policy would make the global file hard to scan.
- Keep plugin-local `keys = { ... }` declarations in `lua/plugins/*.lua` when
  the mapping is purely part of that plugin spec.
- Use a directory-backed domain, such as `vscode/`, once one domain has several
  focused helper modules.

The top-level domain module should stay the public entry point. For example,
`vscode.lua` loads the modules under `vscode/`; callers should not require
those helper modules directly unless they are extending that domain.
