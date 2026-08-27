-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua

-- Vim's default "inclusive" selection includes the character under the cursor,
-- causing off-by-one vs VSCode's between-characters model.
vim.o.selection = "exclusive"
vim.opt.selectmode:append("mouse")
-- LazyVim sets clipboard="" over SSH, breaking Ctrl-C copy to OS clipboard.
-- Force unnamedplus so yanks reach the system clipboard via OSC 52.
vim.o.clipboard = "unnamedplus"

-- Show leading spaces as dim dots.
vim.opt.list = true
vim.opt.listchars:append({ lead = "·" })

-- Match VS Code's editor.rulers = [100] without changing wrapping behavior.
vim.opt.colorcolumn = "100"

-- Blinking block in normal/visual, blinking bar in insert/command.
vim.o.guicursor =
  "n-v-c-sm:blinkon500-blinkoff500-block,i-ci-ve:blinkon500-blinkoff500-ver25,r-cr-o:hor20"

vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.swapfile = false

-- These providers are only needed for old-style remote plugins and direct
-- `:python3`/`:ruby`/`:perl` host commands. Current plugins use Lua, LSPs, or
-- explicit external CLIs instead, so skip provider probing and health noise.
vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0

--- Override in a work overlay to detect large repos where recursive filesystem
--- traversal is prohibitively expensive. With no args, checks the current
--- buffer context. With opts.search_root, returns true only when the given path
--- is itself a large repo root; subdirectory scopes should remain searchable.
function _G.in_large_repo(_path, _opts)
  return false
end
