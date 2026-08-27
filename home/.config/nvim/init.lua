-- bootstrap lazy.nvim, LazyVim and your plugins
if not require("config.lazy-update-lock").await() then
  error("Timed out waiting for the scheduled Lazy plugin update to finish")
end
require("config.lazy")
