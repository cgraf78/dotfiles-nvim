-- Autocmds are automatically loaded on the VeryLazy event.
-- Default autocmds that are always set:
-- https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua

require("config.diagnostics").setup()
require("config.window-focus").setup()
require("config.termnav").setup()
