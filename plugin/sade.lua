if vim.g.loaded_sade then
  return
end
vim.g.loaded_sade = true

-- Plugin is activated via require("sade").setup()
-- This file just guards against double-loading.
