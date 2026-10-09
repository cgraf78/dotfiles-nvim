-- Autocmds are automatically loaded on the VeryLazy event.
-- Default autocmds that are always set:
-- https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua

require("config.diagnostics").setup()
require("config.window-focus").setup()
-- Independent of Termnav's editor setup: forwarding must keep working, and
-- falling back, whatever state the provider's Lua assets are in.
require("config.remote-open").setup()
require("config.termnav").setup()
