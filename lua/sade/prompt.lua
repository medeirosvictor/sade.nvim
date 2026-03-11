local M = {}

local log = require("sade.log")

---@class SadePromptState
local state = {
  bufnr = nil,
  winnr = nil,
  legend_winnr = nil,
  on_submit = nil,
  on_cancel = nil,
}

-- Get UI dimensions
local function get_ui_dimensions()
  local ui = vim.api.nvim_list_uis()[1]
  return ui.width, ui.height
end

-- Open a floating prompt window (99-style with legend footer)
---@param opts { title?: string, default_text?: string, on_submit: fun(prompt: string), on_cancel?: fun() }
function M.open(opts)
  M.close()

  local title = opts.title or "SADE"
  local on_submit = opts.on_submit
  local on_cancel = opts.on_cancel or function() end

  -- Create buffer
  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(bufnr, "sade-prompt")
  state.bufnr = bufnr
  state.on_submit = on_submit
  state.on_cancel = on_cancel

  -- Buffer options - use acwrite to allow BufWriteCmd
  vim.bo[bufnr].buftype = "acwrite"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = "markdown"
  vim.bo[bufnr].modifiable = true

  -- Add default text only (title is in window title)
  local header = {}

  if opts.default_text and opts.default_text ~= "" then
    vim.list_extend(header, vim.split(opts.default_text, "\n"))
    table.insert(header, "")
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, header)

  -- Create centered window config
  local width, height = get_ui_dimensions()
  local win_width = math.floor(width * 0.6)
  local win_height = math.floor(height * 0.4)

  -- Create main floating window
  local winnr = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    width = win_width,
    height = win_height,
    row = math.floor((height - win_height) / 2),
    col = math.floor((width - win_width) / 2),
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

  -- Create legend window at the bottom (like 99)
  local legend_height = 1
  local legend_bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[legend_bufnr].buftype = "nofile"
  vim.bo[legend_bufnr].bufhidden = "wipe"
  vim.bo[legend_bufnr].swapfile = false
  vim.bo[legend_bufnr].modifiable = true

  -- Legend text with key bindings
  local legend_lines = { " :w / Enter = submit  ·  q / Esc = cancel " }
  vim.api.nvim_buf_set_lines(legend_bufnr, 0, -1, false, legend_lines)

  -- Position legend below main window
  local legend_winnr = vim.api.nvim_open_win(legend_bufnr, false, {
    relative = "editor",
    width = #legend_lines[1] + 2,
    height = legend_height,
    row = math.floor((height - win_height) / 2) + win_height + 1,
    col = math.floor((width - win_width) / 2) + 1,
    style = "minimal",
    border = { "", "", "", "", "", "", "", "" },
    zindex = 100,
  })

  state.legend_winnr = legend_winnr

  -- Legend window options
  vim.wo[legend_winnr].wrap = false
  vim.wo[legend_winnr].cursorline = false
  vim.wo[legend_winnr].signcolumn = "no"

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

  -- Enter to submit
  vim.keymap.set("n", "<CR>", function()
    M.submit()
  end, map_opts)

  -- Handle :w and :wq via BufWriteCmd (acwrite requires this)
  local group = vim.api.nvim_create_augroup("sade_prompt", { clear = true })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = group,
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
        M.close()
        on_cancel()
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

  -- Trim leading empty lines
  local prompt_lines = {}
  local started = false
  for _, line in ipairs(all_lines) do
    if not started then
      if vim.trim(line) ~= "" then
        started = true
        table.insert(prompt_lines, line)
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
  -- Close legend window first
  if state.legend_winnr and vim.api.nvim_win_is_valid(state.legend_winnr) then
    vim.api.nvim_win_close(state.legend_winnr, true)
  end

  -- Close main window
  if state.winnr and vim.api.nvim_win_is_valid(state.winnr) then
    vim.api.nvim_win_close(state.winnr, true)
  end

  -- Delete buffer
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    vim.api.nvim_buf_delete(state.bufnr, { force = true })
  end

  state.bufnr = nil
  state.winnr = nil
  state.legend_winnr = nil
  state.on_submit = nil
  state.on_cancel = nil
end

-- Check if prompt is open
function M.is_open()
  return state.bufnr ~= nil and vim.api.nvim_buf_is_valid(state.bufnr)
end

-- Message state (for agent responses)
local msg_state = {
  bufnr = nil,
  winnr = nil,
  legend_winnr = nil,
}

--- Show a message in a floating window (for agent responses)
---@param opts { title?: string, content?: string[], on_close?: fun(), position?: "center" | "top-right" }
function M.show_message(opts)
  M.close_message()

  local title = opts.title or "SADE"
  local content = opts.content or {}
  local on_close = opts.on_close or function() end
  local position = opts.position or "center"

  -- Create buffer
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, "sade-message")
  msg_state.bufnr = bufnr

  -- Buffer options
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = "markdown"
  vim.bo[bufnr].modifiable = true

  -- Calculate window size and position based on content and desired position
  local width, height = get_ui_dimensions()
  local win_width, win_height, row, col

  if position == "top-right" then
    -- Small, top-right corner (like 99)
    win_width = math.floor(width / 4)
    win_height = 3
    row = 1
    col = width - win_width - 1
  else
    -- Center (default)
    win_width = math.floor(width * 0.5)
    local content_height = #content + 4
    win_height = math.min(content_height, math.floor(height * 0.6))
    row = math.floor((height - win_height) / 2)
    col = math.floor((width - win_width) / 2)
  end

  -- Create main floating window
  local winnr = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    width = win_width,
    height = win_height,
    row = row,
    col = col,
    style = "minimal",
    border = position == "top-right" and "rounded" or "rounded",
    title = " " .. title .. " ",
    title_pos = "center",
  })

  msg_state.winnr = winnr

  -- Window options
  vim.wo[winnr].wrap = true
  vim.wo[winnr].cursorline = true
  vim.wo[winnr].scrolloff = 3

  -- Set content
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)

  -- Make buffer read-only (non-editable)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].readonly = true

  -- Create legend window at the bottom
  local legend_bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[legend_bufnr].buftype = "nofile"
  vim.bo[legend_bufnr].bufhidden = "wipe"
  vim.bo[legend_bufnr].swapfile = false
  vim.bo[legend_bufnr].modifiable = true

  local legend_lines = { " press q or Enter to close " }
  vim.api.nvim_buf_set_lines(legend_bufnr, 0, -1, false, legend_lines)

  -- Calculate legend position based on main window
  local legend_row, legend_col
  if position == "top-right" then
    legend_row = row + win_height + 1
    legend_col = col
  else
    legend_row = row + win_height + 1
    legend_col = col + 1
  end

  local legend_winnr = vim.api.nvim_open_win(legend_bufnr, false, {
    relative = "editor",
    width = #legend_lines[1] + 2,
    height = 1,
    row = legend_row,
    col = legend_col,
    style = "minimal",
    border = { "", "", "", "", "", "", "", "" },
    zindex = 100,
  })

  msg_state.legend_winnr = legend_winnr

  vim.wo[legend_winnr].wrap = false
  vim.wo[legend_winnr].cursorline = false
  vim.wo[legend_winnr].signcolumn = "no"

  -- Keymaps
  local map_opts = { buffer = bufnr, silent = true, noremap = true }

  vim.keymap.set("n", "<Esc>", function()
    M.close_message()
    on_close()
  end, map_opts)

  vim.keymap.set("n", "q", function()
    M.close_message()
    on_close()
  end, map_opts)

  vim.keymap.set("n", "<CR>", function()
    M.close_message()
    on_close()
  end, map_opts)

  -- Close on WinClosed
  local group = vim.api.nvim_create_augroup("sade_message", { clear = true })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(winnr),
    callback = function()
      M.close_message()
      on_close()
    end,
  })

  -- Focus the window
  vim.api.nvim_set_current_win(winnr)

  log.debug("Message window opened", { bufnr = bufnr, winnr = winnr })
end

--- Close message window
function M.close_message()
  if msg_state.legend_winnr and vim.api.nvim_win_is_valid(msg_state.legend_winnr) then
    vim.api.nvim_win_close(msg_state.legend_winnr, true)
  end
  if msg_state.winnr and vim.api.nvim_win_is_valid(msg_state.winnr) then
    vim.api.nvim_win_close(msg_state.winnr, true)
  end
  if msg_state.bufnr and vim.api.nvim_buf_is_valid(msg_state.bufnr) then
    vim.api.nvim_buf_delete(msg_state.bufnr, { force = true })
  end
  msg_state.bufnr = nil
  msg_state.winnr = nil
  msg_state.legend_winnr = nil
end

--- Check if message is open
function M.is_message_open()
  return msg_state.bufnr ~= nil and vim.api.nvim_buf_is_valid(msg_state.bufnr)
end

return M
