-- Minimal init for running tests in headless nvim.
-- Adds the plugin to runtimepath so require("sade.*") works.
local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.opt.runtimepath:prepend(plugin_root)
