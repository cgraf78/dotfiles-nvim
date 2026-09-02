local M = {}

local shdeps_cache = nil
local dep_root_cache = {}

local function source_path()
  local info = debug.getinfo(1, "S")
  local source = info and info.source or ""
  return source:gsub("^@", "")
end

local function dot_home()
  local home = source_path():match("^(.*)/%.config/nvim/lua/config/dot%-runtime%.lua$")
  if home and home ~= "" then
    return home
  end
  return vim.env.HOME or os.getenv("HOME") or ""
end

function M.shdeps()
  if not shdeps_cache then
    local home = dot_home()
    local lua_dir = os.getenv("SHDEPS_LUA_DIR")
    if type(lua_dir) ~= "string" or lua_dir == "" then
      lua_dir = home .. "/.local/lib/shdeps"
    end

    -- Shdeps owns this stable bootstrap link and retargets it whenever the
    -- active implementation changes. Dotfiles therefore supplies only its
    -- effective home; source/release discovery remains provider policy.
    shdeps_cache = dofile(lua_dir .. "/shdeps/bootstrap.lua").new({ home = home })
  end
  return shdeps_cache
end

local function valid_relpath(relpath)
  if type(relpath) ~= "string" or relpath == "" or relpath:find("\0", 1, true) then
    return false
  end
  if relpath:match("^[/\\]") or relpath:match("^%a:[/\\]") then
    return false
  end
  for part in relpath:gmatch("[^/\\]+") do
    if part == ".." then
      return false
    end
  end
  return true
end

-- Resolve the dependency once per Neovim process, then keep repeated schema
-- and adapter lookups in-process. The relative-path checks preserve dep-file's
-- lexical boundary before joining against the trusted dependency root.
function M.dep_file(repo, relpath)
  if not valid_relpath(relpath) then
    return nil
  end

  local root = dep_root_cache[repo]
  if root == false then
    return nil
  end
  if root == nil then
    root = M.shdeps().dep_root(repo)
    if type(root) ~= "string" or root == "" then
      -- Collapse a synchronous startup batch without making absence sticky for
      -- the lifetime of a long-running editor. A later event-loop turn can
      -- discover a dependency installed by `dot update` while Neovim is open.
      dep_root_cache[repo] = false
      vim.schedule(function()
        if dep_root_cache[repo] == false then
          dep_root_cache[repo] = nil
        end
      end)
      return nil
    end
    dep_root_cache[repo] = root
  end

  local path = vim.fs.joinpath(root, relpath)
  local stat = (vim.uv or vim.loop).fs_stat(path)
  if not stat or stat.type ~= "file" or vim.fn.filereadable(path) ~= 1 then
    return nil
  end
  return path
end

-- Resolve a shdeps-managed dependency file and load it via dofile. Errors when
-- the file is missing unless opts.optional is set, in which case it returns nil
-- so adapters that degrade gracefully can fall back to other behavior.
function M.load_dep(repo, relpath, opts)
  opts = opts or {}
  local path = M.dep_file(repo, relpath)
  if not path then
    if opts.optional then
      return nil
    end
    error(repo .. "/" .. relpath .. " not found through shdeps")
  end
  return dofile(path)
end

return M
