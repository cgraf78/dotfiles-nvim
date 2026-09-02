local function workspace_files()
  require("nvim_workspace").files()
end

local function workspace_repo_files()
  local workspace = require("nvim_workspace")
  workspace.files({ root = workspace.current_file_repo_root() })
end

local function workspace_grep()
  require("nvim_workspace").grep()
end

local function workspace_explorer()
  local paths = require("nvim_workspace.neo_tree")
  paths.open(paths.context_root(), { action = "focus" })
end

return {
  {
    "cgraf78/nvim-workspace",
    init = function()
      -- Install editor-owned workspace mappings after LazyVim's defaults. A
      -- higher overlay may extend this module with development-only mappings.
      vim.api.nvim_create_autocmd("User", {
        pattern = "VeryLazy",
        callback = function()
          vim.schedule(function()
            require("config.keymaps.workspace").setup()
          end)
        end,
      })
    end,
    opts = function()
      return require("config.nvim-workspace").options()
    end,
    config = function(_, opts)
      require("nvim_workspace").setup(opts)
    end,
  },

  -- nvim-workspace owns restore/save timing so the launch-cwd session and
  -- file-root aliases are updated together through one policy boundary.
  {
    "folke/persistence.nvim",
    opts = {},
    config = function(_, opts)
      local persistence = require("persistence")
      -- This is the branch hook used by persistence.current() in the pinned
      -- plugin version; keep the override next to setup so lock updates must
      -- preserve the fast session-name path.
      persistence.branch = require("config.nvim-workspace").persistence_branch
      persistence.setup(opts)
      -- Own quit-time saves in nvim-workspace so the primary session
      -- and file-root aliases are written together without a duplicate primary
      -- `:mksession` from persistence.nvim's default VimLeavePre autocmd.
      persistence.stop()
    end,
  },

  -- in_large_repo() (defined in options.lua, overridable by overlay configs)
  -- disables git status and gitignore filtering that would be too slow in
  -- very large repositories. Neo-tree's libuv watcher stays off globally:
  -- opening broad trees can otherwise exhaust file descriptors with EMFILE.
  {
    "nvim-neo-tree/neo-tree.nvim",
    keys = {
      {
        "<leader>fe",
        function()
          require("nvim_workspace.neo_tree").open(nil, { toggle = true })
        end,
        desc = "Explorer NeoTree (Home)",
      },
      {
        "<leader>fE",
        workspace_explorer,
        desc = "Explorer NeoTree (Workspace Root)",
      },
      { "<C-S-e>", workspace_explorer, desc = "Explorer NeoTree (Workspace Root)" },
    },
    opts = function()
      local paths = require("nvim_workspace.neo_tree")
      paths.setup_manager_patch()
      local policy = paths.filesystem_policy()
      return {
        enable_git_status = policy.enable_git_status,
        filesystem = {
          -- Keep the sidebar responsive while its shallow root scan fills in.
          async_directory_scan = "always",
          use_libuv_file_watcher = false,
          follow_current_file = { enabled = true },
          filtered_items = policy.filtered_items,
          window = {
            mappings = paths.filesystem_mappings(),
          },
        },
      }
    end,
  },

  -- Workspace pickers live in nvim-workspace so this config only owns the
  -- key/command surface. Overlay configs can still register additional sources
  -- through the plugin's public extension API.
  {
    "nvim-telescope/telescope.nvim",
    init = function()
      local function root_arg(opts)
        return opts.args ~= "" and opts.args or nil
      end

      vim.api.nvim_create_user_command("FindFilesIn", function(opts)
        require("nvim_workspace").files({ root = root_arg(opts) })
      end, { nargs = "?", complete = "dir", desc = "Find files under a directory" })

      vim.api.nvim_create_user_command("FileSearchIn", function(opts)
        require("nvim_workspace").grep({ root = root_arg(opts) })
      end, { nargs = "?", complete = "dir", desc = "Search file contents under a directory" })
    end,
    opts = {
      pickers = {
        buffers = {
          mappings = {
            n = {
              ["dd"] = function(buf)
                require("telescope.actions").delete_buffer(buf)
              end,
            },
          },
        },
      },
    },
    keys = {
      { "<C-p>", workspace_files, desc = "Find files" },
      { "<leader><space>", workspace_files, desc = "Find files" },
      { "<leader>ff", workspace_files, desc = "Find files" },
      { "<leader>fF", workspace_repo_files, desc = "Find files (Repository)" },
      { "<leader>fg", workspace_grep, desc = "Search in files" },
      -- Ctrl-F is reserved for VSCode-style in-buffer find in config/keymaps;
      -- Telescope keeps Ctrl-P and Ctrl-Shift-F for workspace-scale search.
      { "<C-S-f>", workspace_grep, desc = "Search in files" },
      {
        "<C-S-p>",
        function()
          require("config.command-palette").open()
        end,
        desc = "Command palette",
      },
    },
  },
}
