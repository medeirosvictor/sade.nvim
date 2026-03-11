local M = {}

local log = require("sade.log")

---@class SadePromptState
local state = {
  bufnr = nil,
  winnr = nil,
  on_submit = nil,
  on_cancel = nil,
  should_close = false,
}

-- Get UI dimensions
local function get_ui_dimensions()
  local ui = vim.api.nvim_list_uis()[1]
  return ui.width, ui.height
end

-- Create centered window config
local function create_centered_config()
  local width, height = get_ui_dimensions()
  local win_width = math.floor(width * 0.6)
  local win_height = math.floor(height * 0.4)
  return {
    width = win_width,
    height = win_height,
    row = math.floor((height - win_height) / 2),
    col = math.floor((width - win_width) / 2),
  }
end

-- Open a floating prompt window (99-style)
---@param opts { title?: string, default_text?: string, on_submit: fun(prompt: string), on_cancel?: fun() }
function M.open(opts)
  -- Close any existing prompt
  M.close()

  local title = opts.title or "SADE"
  local on_submit = opts.on_submit
  local on_cancel = opts.on_cancel or function() end

  -- Create buffer
  local bufnr = vim.api.nvim_create_buf(true, false)
  state.bufnr = bufnr
  state.on_submit = on_submit
  state.on_cancel = on_cancel

  -- Buffer options
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = "markdown"
  vim.bo[bufnr].modifiable = true

  -- Add header
  local header = {
    "# " .. title,
    "",
    "Write your prompt above, then :w to submit",
    "Press q or Escape to cancel",
    "",
    "────────────────────────────────────────────",
    "",
  }

  if opts.default_text and opts.default_text ~= "" then
    vim.list_extend(header, vim.split(opts.default_text, "\n"))
    table.insert(header, "")
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, header)

  -- Create floating window
  local config = create_centered_config()
  local winnr = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    width = config.width,
    height = config.height,
    row = config.row,
    col = config.col,
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " ",
    title_pos = "center",
  })

  state.winnr = winnr

  -- Window options
  vim.wo[winnr].wrap = true
  vim.wo[winnr].cursorline = true
  vim.wo[winnr].scrolloff = 3

  -- Keymaps
  local map_opts = { buffer = bufnr, silent = true, noremap = true }

  -- Escape or q to cancel
  vim.keymap.set("n", "<Esc>", function()
    M.close()
    on_cancel()
  end, map_opts)

  vim.keymap.set("n", "q", function()
    M.close()
    on_cancel()
  end, map_opts)

  -- :w to submit
  vim.keymap.set("n", "<CR>", function()
    M.submit()
  end, map_opts)

  -- Custom command for :w
  vim.api.nvim_buf_create_user_command(bufnr, "SadePromptSubmit", function()
    M.submit()
  end, {})

  -- Handle :w and :wq
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = bufnr,
    callback = function()
      M.submit()
    end,
  })

  -- Close on WinClosed
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(winnr),
    callback = function()
      if state.bufnr == bufnr then
        state.bufnr = nil
        state.winnr = nil
      end
    end,
  })

  -- Focus and start insert
  vim.api.nvim_set_current_win(winnr)
  vim.cmd("startinsert")

  log.debug("Prompt window opened", { bufnr = bufnr, winnr = winnr })
end

-- Submit the current prompt
function M.submit()
  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then
    return
  end

  local bufnr = state.bufnr
  local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Skip header (lines starting with # or ─)
  local prompt_lines = {}
  local in_header = true
  for _, line in ipairs(all_lines) do
    local trimmed = vim.trim(line)
    if in_header then
      if trimmed == "" then
        -- Allow empty lines in header
      elseif trimmed:match("^#") then
        -- Skip title
      elseif trimmed:match("^─") or trimmed:match("^-$") then
        in_header = false
      end
    else
      table.insert(prompt_lines, line)
    end
  end

  local prompt = table.concat(prompt_lines, "\n"):gsub("\n+$", ""):gsub("^\n+", "")

  if prompt == "" or vim.trim(prompt) == "" then
    vim.notify("[sade] prompt is empty", vim.log.levels.WARN)
    return
  end

  -- Store callback before closing
  local cb = state.on_submit

  -- Close window
  M.close()

  -- Submit
  if cb then
    cb(prompt)
  end
end

-- Close the prompt without submitting
function M.close()
  -- Close window first
  if state.winnr and vim.api.nvim_win_is_valid(state.winnr) then
    vim.api.nvim_win_close(state.winnr, true)
  end

  -- Delete buffer
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    vim.api.nvim_buf_delete(state.bufnr, { force = true })
  end

  state.bufnr = nil
  state.winnr = nil
  state.on_submit = nil
  state.on_cancel = nil
end

-- Check if prompt is open
function M.is_open()
  return state.bufnr ~= nil and vim.api.nvim_buf_is_valid(state.bufnr)
end

return M
