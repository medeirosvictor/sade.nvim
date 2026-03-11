local M = {}

local config = require("sade.config")

local SPINNER_FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local SIGN_GROUP = "sade_heartbeat"

---@class SadeSpinner
---@field ns number|nil namespace id
---@field timer uv_timer_t|nil
---@field frame number
local Spinner = {}
Spinner.__index = Spinner

function Spinner.new()
  return setmetatable({
    ns = nil,
    timer = nil,
    frame = 1,
  }, Spinner)
end

--- Define signs for each spinner frame + stale state.
function Spinner:ensure_signs()
  if self.ns then
    return
  end
  self.ns = vim.api.nvim_create_namespace("sade_heartbeat")

  -- Define salmon-pink highlight groups for read signs
  vim.api.nvim_set_hl(0, "SadeReadSign", { fg = "#E9967A", bold = true })       -- salmon-pink (dark salmon)
  vim.api.nvim_set_hl(0, "SadeReadStaleSign", { fg = "#F08080", italic = true }) -- light salmon (dimmer)

  for i, frame in ipairs(SPINNER_FRAMES) do
    vim.fn.sign_define("SadeSpinner" .. i, { text = frame, texthl = "DiagnosticWarn" })
  end
  -- dim persistent indicator for files that were changed but settled
  vim.fn.sign_define("SadeStale", { text = "●", texthl = "DiagnosticHint" })
  -- salmon-pink for files actively being read
  vim.fn.sign_define("SadeRead", { text = "○", texthl = "SadeReadSign" })
  -- dim salmon-pink for files that were read but settled
  vim.fn.sign_define("SadeReadStale", { text = "○", texthl = "SadeReadStaleSign" })
end

--- Find buffer number for a file path, if loaded.
---@param filepath string
---@return number|nil
local function find_buf(filepath)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      if vim.api.nvim_buf_get_name(buf) == filepath then
        return buf
      end
    end
  end
  return nil
end

--- Place the current spinner frame sign on all active buffers.
---@param active_files table<string, number> filepath -> timestamp
function Spinner:tick(active_files)
  self.frame = (self.frame % #SPINNER_FRAMES) + 1
  local sign_name = "SadeSpinner" .. self.frame

  for filepath, _ in pairs(active_files) do
    local bufnr = find_buf(filepath)
    if bufnr then
      vim.fn.sign_unplace(SIGN_GROUP, { buffer = bufnr })
      vim.fn.sign_place(0, SIGN_GROUP, sign_name, bufnr, { lnum = 1, priority = 50 })
    end
  end
end

--- Start the spinner animation loop.
function Spinner:start(active_files_callback)
  if self.timer then
    return
  end
  self:ensure_signs()
  local interval = config.values.heartbeat.spinner_ms
  self.timer = vim.uv.new_timer()
  self.timer:start(0, interval, function()
    vim.schedule(function()
      self:tick(active_files_callback())
    end)
  end)
end

--- Stop the spinner animation loop.
function Spinner:stop()
  if self.timer then
    self.timer:stop()
    self.timer:close()
    self.timer = nil
  end
end

--- Place stale sign on a buffer.
---@param filepath string
function Spinner:place_stale(filepath)
  local bufnr = find_buf(filepath)
  if bufnr then
    vim.fn.sign_unplace(SIGN_GROUP, { buffer = bufnr })
    vim.fn.sign_place(0, SIGN_GROUP, "SadeStale", bufnr, { lnum = 1, priority = 50 })
  end
end

--- Clear stale sign from a buffer.
---@param filepath string
function Spinner:clear_stale(filepath)
  local bufnr = find_buf(filepath)
  if bufnr then
    vim.fn.sign_unplace(SIGN_GROUP, { buffer = bufnr })
  end
end

--- Place active read sign on a buffer (currently being read).
---@param filepath string
function Spinner:place_read(filepath)
  local bufnr = find_buf(filepath)
  if bufnr then
    vim.fn.sign_unplace(SIGN_GROUP, { buffer = bufnr })
    vim.fn.sign_place(0, SIGN_GROUP, "SadeRead", bufnr, { lnum = 1, priority = 50 })
  end
end

--- Place stale read sign on a buffer (read but settled).
---@param filepath string
function Spinner:place_read_stale(filepath)
  local bufnr = find_buf(filepath)
  if bufnr then
    vim.fn.sign_unplace(SIGN_GROUP, { buffer = bufnr })
    vim.fn.sign_place(0, SIGN_GROUP, "SadeReadStale", bufnr, { lnum = 1, priority = 50 })
  end
end

--- Clear all signs.
function Spinner:clear_all()
  vim.fn.sign_unplace(SIGN_GROUP)
end

--- Get all buffers with signs in this group.
---@return table<number, number[]> buffer -> sign ids
function Spinner:get_signs()
  local result = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local signs = vim.fn.sign_getplaced(buf, { group = SIGN_GROUP })[1]
      if signs then
        local ids = {}
        for _, s in ipairs(signs.signs) do
          table.insert(ids, s.id)
        end
        if #ids > 0 then
          result[buf] = ids
        end
      end
    end
  end
  return result
end

M.Spinner = Spinner

return M
