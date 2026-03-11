local M = {}

local log = require("sade.log")

---@class SadePromptBuffer
---@field bufnr number
---@field on_submit fun(prompt: string): nil
---@field on_cancel fun(): nil

local state = {
  bufnr = nil,
  on_submit = nil,
  on_cancel = nil,
  ns = nil,
}

--- Create a prompt buffer that submits on :w/:q and cancels on Escape
---@param opts { title?: string, default_text?: string, on_submit: fun(prompt: string), on_cancel?: fun() }
---@return number bufnr
function M.open(opts)
  -- Close any existing prompt buffer
  M.close()

  local title = opts.title or "SADE · Prompt"
  local on_submit = opts.on_submit
  local on_cancel = opts.on_cancel or function() end

  -- Create new buffer
  local bufnr = vim.api.nvim_create_buf(true, false)
  state.bufnr = bufnr
  state.on_submit = on_submit
  state.on_cancel = on_cancel

  -- Set buffer options
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = "sade_prompt"
  vim.bo[bufnr].modifiable = true

  -- Add default text if provided
  if opts.default_text and opts.default_text ~= "" then
    local lines = vim.split(opts.default_text, "\n", { plain = true })
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  end

  -- Open in a split
  vim.cmd("topleft new")
  local winnr = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(winnr, bufnr)

  -- Window options
  vim.wo[winnr].number = false
  vim.wo[winnr].relativenumber = false
  vim.wo[winnr].wrap = true
  vim.wo[winnr].cursorline = true

  -- Set buffer local options
  vim.bo[bufnr].filetype = "markdown"  -- Better highlighting

  -- Create namespace for highlights
  state.ns = vim.api.nvim_create_namespace("sade_prompt")

  -- Add header comment
  local header = {
    "# " .. title,
    "",
    "# Write and quit to submit (:w + :q)",
    "# Press Escape to cancel",
    "",
    "---",
    "",
  }
  vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, header)

  -- Keymaps for the buffer
  local map_opts = { buffer = bufnr, silent = true, noremap = true }

  -- Escape to cancel
  vim.keymap.set("n", "<Esc>", function()
    M.close()
    on_cancel()
  end, map_opts)

  -- :q to cancel (but not :q!)
  vim.keymap.set("n", "q", function()
    -- Only cancel if not modified or user confirms
    if vim.bo[bufnr].modified then
      vim.cmd("confirm quit")
    else
      M.close()
      on_cancel()
    end
  end, map_opts)

  -- :w to save (submit)
  vim.keymap.set("n", "<CR>", function()
    M.submit()
  end, map_opts)

  -- Custom commands
  vim.api.nvim_buf_create_user_command(bufnr, "SadePromptSubmit", function()
    M.submit()
  end, {})

  vim.api.nvim_buf_create_user_command(bufnr, "SadePromptCancel", function()
    M.close()
    on_cancel()
  end, {})

  -- Set up auto-command for :w + :q combo
  -- When buffer is written, check if we should submit
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = bufnr,
    callback = function()
      -- Get the prompt content (after the header)
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      -- Skip header lines (lines starting with # or ---)
      local prompt_lines = {}
      local in_header = true
      for _, line in ipairs(lines) do
        local trimmed = vim.trim(line)
        if in_header then
          if trimmed == "---" then
            in_header = false
          end
        else
          table.insert(prompt_lines, line)
        end
      end

      local prompt = table.concat(prompt_lines, "\n"):trim()

      if prompt == "" then
        vim.notify("[sade] prompt is empty", vim.log.levels.WARN)
        return
      end

      -- Check if this was a :w (write) or :wq (write + quit)
      -- If it was just :w, keep the buffer open
      -- If it was :wq or :x, close and submit
    end,
  })

  -- Track if we should close after write
  local should_close = false

  vim.api.nvim_create_autocmd("BufWinLeave", {
    buffer = bufnr,
    callback = function()
      if vim.bo[bufnr].modified and not should_close then
        -- Buffer was modified and being closed - check if we should submit
        return
      end
    end,
  })

  -- Override :wq and :x to submit
  vim.keymap.set("n", "Z", function()
    should_close = true
    vim.cmd("write")
    vim.cmd("quit")
  end, map_opts)

  vim.api.nvim_buf_create_user_command(bufnr, "SadePromptDone", function()
    should_close = true
    vim.cmd("write")
    vim.cmd("quit")
  end, {})

  -- Focus the buffer
  vim.api.nvim_set_current_win(winnr)
  vim.cmd("startinsert")

  log.debug("Prompt buffer opened", { bufnr = bufnr })

  return bufnr
end

--- Submit the current prompt buffer
function M.submit()
  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then
    return
  end

  local bufnr = state.bufnr

  -- Get the prompt content (after the header)
  local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Skip header lines (lines starting with # or ---)
  local prompt_lines = {}
  local in_header = true
  for _, line in ipairs(all_lines) do
    local trimmed = vim.trim(line)
    if in_header then
      if trimmed == "---" then
        in_header = false
      end
    else
      table.insert(prompt_lines, line)
    end
  end

  local prompt = table.concat(prompt_lines, "\n"):trim()

  if prompt == "" then
    vim.notify("[sade] prompt is empty", vim.log.levels.WARN)
    return
  end

  -- Store the callback
  local cb = state.on_submit

  -- Close the buffer
  M.close()

  -- Call the submit callback
  if cb then
    cb(prompt)
  end
end

--- Close the prompt buffer without submitting
function M.close()
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    -- Force close without saving
    vim.api.nvim_buf_delete(state.bufnr, { force = true })
  end
  state.bufnr = nil
  state.on_submit = nil
  state.on_cancel = nil
end

--- Check if a prompt buffer is currently open
---@return boolean
function M.is_open()
  return state.bufnr ~= nil and vim.api.nvim_buf_is_valid(state.bufnr)
end

return M
