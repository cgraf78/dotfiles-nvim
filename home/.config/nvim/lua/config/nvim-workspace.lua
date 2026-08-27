local M = {}

local shell_glob = "*@(.sh|.inc|.bash|.zsh|.command)"
local shell_filetypes = { "bash", "sh", "zsh" }
local vcs_markers = { ".git", ".hg", ".jj", ".svn" }
local dotfiles_tracked_cache = nil

local home_files = {
  ".bashrc",
  ".bash_profile",
  ".profile",
  ".zshenv",
  ".zprofile",
  ".zshrc",
}

-- HOME shell indexing must stay aligned with the VS Code HOME workspace
-- policy in ~/.vscode/settings.json. The shdeps bin glob indexes installed
-- targets instead of the ~/.local/bin symlink facade, while .local/bin stays a
-- direct-open path below.
local home_globs = {
  ".local/share/cgraf78/*/bin/*",
}

local home_dirs = {
  {
    prefix = ".config/dot/merge-hooks.d/",
    glob = ".config/dot/merge-hooks.d/**/" .. shell_glob,
  },
  {
    prefix = ".config/shdeps/hooks.d/",
    glob = ".config/shdeps/hooks.d/**/" .. shell_glob,
  },
  {
    prefix = ".config/shell/",
    glob = ".config/shell/**/" .. shell_glob,
  },
  {
    prefix = ".local/share/cgraf78/",
    glob = ".local/share/cgraf78/**/" .. shell_glob,
  },
  {
    prefix = ".local/bin/",
    direct = true,
  },
}

local function strip_trailing_slash(path)
  if path == "/" then
    return path
  end
  return (path:gsub("/+$", ""))
end

local function home()
  return strip_trailing_slash(vim.fn.fnamemodify(vim.env.HOME or "~", ":p"))
end

local function dotfiles_git_dir()
  return home() .. "/.dotfiles"
end

local function normalize_dir(path)
  return strip_trailing_slash(vim.fn.fnamemodify(path, ":p"))
end

local function read_first_line(path)
  local ok, lines = pcall(vim.fn.readfile, path, "", 1)
  if not ok then
    return nil
  end
  return lines[1]
end

-- persistence.nvim asks for the branch once per primary and alias session
-- save. Reading Git's symbolic HEAD preserves its branch-session naming while
-- avoiding a PATH launcher process for every root in the save batch.
function M.persistence_branch(cwd)
  local root = normalize_dir(cwd or vim.fn.getcwd())
  local marker = root .. "/.git"
  local marker_stat = vim.uv.fs_stat(marker)
  if not marker_stat then
    return nil
  end

  local git_dir = marker
  if marker_stat.type == "file" then
    local target = (read_first_line(marker) or ""):match("^gitdir:%s*(.-)%s*$")
    if not target or target == "" then
      return nil
    end
    if not target:match("^/") then
      target = vim.fs.dirname(marker) .. "/" .. target
    end
    git_dir = normalize_dir(target)
  elseif marker_stat.type ~= "directory" then
    return nil
  end

  local head = read_first_line(git_dir .. "/HEAD")
  return head and head:match("^ref:%s*refs/heads/(.-)%s*$") or nil
end

local function contains(root, path)
  root = normalize_dir(root)
  path = normalize_dir(path)
  return path == root or path:sub(1, #root + 1) == root .. "/"
end

local function marker_root(cwd)
  local marker = vim.fs.find(vcs_markers, { path = cwd, upward = true, limit = 1 })[1]
  if marker then
    local root = normalize_dir(vim.fs.dirname(marker))
    if root ~= home() then
      return root
    end
  end
  return nil
end

local function option_marker_root(opts)
  if type(opts) == "table" and type(opts.marker_root) == "string" and opts.marker_root ~= "" then
    local root = normalize_dir(opts.marker_root)
    if root ~= home() then
      return root
    end
  end
  return nil
end

local function dotfiles_index_identity(git_dir)
  if vim.env.GIT_INDEX_FILE and vim.env.GIT_INDEX_FILE ~= "" then
    return nil
  end

  local stat = vim.uv.fs_stat(git_dir .. "/index")
  if not stat or stat.type ~= "file" or not stat.mtime or not stat.ctime then
    return nil
  end

  local fields = {
    stat.dev,
    stat.ino,
    stat.size,
    stat.mtime.sec,
    stat.mtime.nsec,
    stat.ctime.sec,
    stat.ctime.nsec,
  }
  for _, field in ipairs(fields) do
    if field == nil then
      return nil
    end
  end
  return table.concat(fields, ":")
end

local function dotfiles_tracked_root(cwd)
  local root = home()
  if not contains(root, cwd) then
    return nil
  end

  local git_dir = dotfiles_git_dir()
  local stat = vim.uv.fs_stat(git_dir)
  if not stat or stat.type ~= "directory" then
    return nil
  end

  local normalized = normalize_dir(cwd)
  if normalized == root then
    return root
  end

  local rel = normalized:sub(#root + 2)
  local cwd_stat = vim.uv.fs_stat(normalized)
  local index_identity = dotfiles_index_identity(git_dir)
  local cache_key = index_identity
      and table.concat(
        { normalized, cwd_stat and cwd_stat.type or "missing", index_identity },
        "\0"
      )
    or nil
  if cache_key and dotfiles_tracked_cache and dotfiles_tracked_cache.key == cache_key then
    return dotfiles_tracked_cache.root or nil
  end

  local args = {
    "git",
    "-C",
    root,
    "--git-dir",
    git_dir,
    "--work-tree",
    root,
    "ls-files",
    "--",
    rel,
  }
  if cwd_stat and cwd_stat.type == "directory" then
    args[#args + 1] = rel .. "/**"
  end

  local tracked = vim.fn.system(args)
  if vim.v.shell_error ~= 0 then
    return nil
  end

  local tracked_root = tracked ~= "" and root or false
  -- Workspace pickers commonly ask about the same path several times in one
  -- interaction. Keep only that result in memory, and bind it to the complete
  -- client-index identity so staging or atomic index replacement invalidates it.
  if cache_key then
    dotfiles_tracked_cache = { key = cache_key, root = tracked_root }
  end
  return tracked_root or nil
end

local function dotfiles_root(cwd)
  return dotfiles_tracked_root(cwd)
end

function M.options()
  return {
    large_root_detector = function(root, opts)
      return _G.in_large_repo(root, opts)
    end,
    workspace = {
      ignored_marker_roots = { home() },
      repo_root_detector = function(cwd, opts)
        return option_marker_root(opts) or marker_root(cwd)
      end,
      home_workspace_detector = function(cwd)
        return dotfiles_root(cwd)
      end,
    },
    session = {
      save_debounce_ms = 500,
    },
    shell = {
      shell_glob = shell_glob,
      file_globs = { "*.sh", "*.inc", "*.bash", "*.zsh", "*.command" },
      home_files = home_files,
      home_globs = home_globs,
      home_dirs = home_dirs,
      overlay = {
        enabled = true,
        root_prefix = ".dotfiles-",
        home_dir = "home",
      },
    },
    navigation = {
      path_first_filetypes = shell_filetypes,
      shell_filetypes = shell_filetypes,
      shell_module = "nvim_workspace.shell",
      prefer_shell_for_home_paths = true,
    },
  }
end

return M
