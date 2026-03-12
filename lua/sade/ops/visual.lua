local log = require("sade.log")
local config = require("sade.config")

-- Extmark namespace for visual selection marks
local NS = vim.api.nvim_create_namespace("sade_visual")

-- Spinner frames (same as throbber)
local SPINNER_FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

---@class VisualState
---@field bufnr number buffer being modified
---@field start_row number 0-indexed start row
---@field start_col number 0-indexed start column
---@field end_row number 0-indexed end row
---@field end_col number 0-indexed end column
---@field top_extmark number extmark id for top spinner
---@field bottom_extmark number extmark id for bottom spinner
---@field spinner_timer uv_timer_t
---@field spinner_frame number
local state = {}

--- Get the current visual selection
--- The '< and '> marks persist after exiting visual mode,
--- so this works when called from a command after visual selection.
---@return { bufnr: number, start_row: number, start_col: number, end_row: number, end_col: number }|nil
local function get_visual_selection()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Get the selection marks ('< and '> persist after exiting visual mode)
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  -- Check if marks are set (row 0 means not set)
  if start_pos[2] == 0 and end_pos[2] == 0 then
    return nil
  end

  local start_row = start_pos[2] - 1  -- Convert to 0-indexed
  local start_col = start_pos[3] - 1
  local end_row = end_pos[2] - 1
  local end_col = end_pos[3] - 1

  -- Handle visual line mode (V) - check current mode or infer from column
  -- If start_col is 0 and end_col spans entire lines, it was likely V mode
  local mode = vim.fn.mode()
  if mode == "V" or (start_col == 0 and end_col == 0) then
    -- Select whole lines
    local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
    end_col = 0
    if #lines > 0 then
      end_col = #lines[#lines]
    end
    end_row = start_row + #lines - 1
  end

  return {
    bufnr = bufnr,
    start_row = start_row,
    start_col = start_col,
    end_row = end_row,
    end_col = end_col,
  }
end

--- Place extmarks at the start and end of the selection
---@param sel { bufnr: number, start_row: number, start_col: number, end_row: number, end_col: number }
---@return { top: number, bottom: number } extmark ids
local function place_extmarks(sel)
  -- Place extmark at start (top spinner)
  local top_id = vim.api.nvim_buf_set_extmark(sel.bufnr, NS, sel.start_row, sel.start_col, {
    id = 1,
    virt_text = { { "⠋ Implementing...", "Comment" } },
    virt_text_pos = "eol",
  })

  -- Place extmark at end (bottom spinner)
  local bottom_id = vim.api.nvim_buf_set_extmark(sel.bufnr, NS, sel.end_row, sel.end_col, {
    id = 2,
    virt_text = { { "⠋", "Comment" } },
    virt_text_pos = "eol",
  })

  return { top = top_id, bottom = bottom_id }
end

--- Update spinner animation
local function tick_spinner()
  if not state.spinner_timer then
    return
  end

  state.spinner_frame = (state.spinner_frame % #SPINNER_FRAMES) + 1
  local icon = SPINNER_FRAMES[state.spinner_frame]

  -- Update both extmarks
  if state.top_extmark then
    vim.api.nvim_buf_set_extmark(state.bufnr, NS, state.start_row, state.start_col, {
      id = 1,
      virt_text = { { icon .. " Implementing...", "Comment" } },
      virt_text_pos = "eol",
    })
  end

  if state.bottom_extmark then
    vim.api.nvim_buf_set_extmark(state.bufnr, NS, state.end_row, state.end_col, {
      id = 2,
      virt_text = { { icon, "Comment" } },
      virt_text_pos = "eol",
    })
  end
end

--- Start spinner animation
local function start_spinner()
  if state.spinner_timer then
    return
  end

  local interval = config.values.heartbeat.spinner_ms or 80
  state.spinner_timer = vim.uv.new_timer()
  state.spinner_timer:start(0, interval, function()
    vim.schedule(tick_spinner)
  end)
end

--- Stop spinner animation
local function stop_spinner()
  if state.spinner_timer then
    state.spinner_timer:stop()
    state.spinner_timer:close()
    state.spinner_timer = nil
  end
end

--- Clear extmarks
local function clear_extmarks()
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    vim.api.nvim_buf_clear_namespace(state.bufnr, NS, 0, -1)
  end
  state.top_extmark = nil
  state.bottom_extmark = nil
end

--- Execute visual mode prompt with the agent
---@param sade_root string
---@param idx any
---@param opts { prompt: string }|nil
local function run_visual(sade_root, idx, opts)
  opts = opts or {}

  -- Check for visual selection
  local sel = get_visual_selection()
  if not sel then
    vim.notify("[sade] No visual selection", vim.log.levels.WARN)
    return
  end

  -- Store state
  state.bufnr = sel.bufnr
  state.start_row = sel.start_row
  state.start_col = sel.start_col
  state.end_row = sel.end_row
  state.end_col = sel.end_col
  state.spinner_frame = 1

  -- Get the selected text
  local selected_text
  if sel.start_row == sel.end_row then
    -- Single line
    local line = vim.api.nvim_buf_get_lines(sel.bufnr, sel.start_row, sel.start_row + 1, false)[1]
    selected_text = line:sub(sel.start_col + 1, sel.end_col)
  else
    -- Multiple lines
    local lines = vim.api.nvim_buf_get_lines(sel.bufnr, sel.start_row, sel.end_row + 1, false)
    -- Adjust first line
    lines[1] = lines[1]:sub(sel.start_col + 1)
    -- Adjust last line
    local last_line = lines[#lines]
    lines[#lines] = last_line:sub(1, sel.end_col)
    selected_text = table.concat(lines, "\n")
  end

  log.debug("Visual selection", {
    rows = sel.end_row - sel.start_row + 1,
    text_len = #selected_text,
  })

  -- Place extmarks with spinner
  local marks = place_extmarks(sel)
  state.top_extmark = marks.top
  state.bottom_extmark = marks.bottom

  -- Start spinner
  start_spinner()

  -- Create cleanup function
  local cleanup = function()
    stop_spinner()
    clear_extmarks()
  end

  -- Build the prompt with selection
  local prompt = opts.prompt or ""
  local full_prompt = prompt .. "\n\n```\n" .. selected_text .. "\n```"

  -- Get agent module
  local agent = require("sade.agent")

  -- We need to modify agent.invoke to support visual mode
  -- For now, let's call it with a special flag
  -- TODO: Extend agent.invoke to handle visual mode

  -- Exit visual mode first
  vim.cmd("normal! <Esc>")

  -- Invoke the agent with the selection as context
  -- This will be handled by agent.invoke internally
  agent.invoke(sade_root, idx, {
    prompt = full_prompt,
    selection = {
      bufnr = sel.bufnr,
      start_row = sel.start_row,
      start_col = sel.start_col,
      end_row = sel.end_row,
      end_col = sel.end_col,
    },
    on_start = function()
      -- Spinner already started
    end,
    on_stdout = function(line)
      -- Could stream to virtual text here
    end,
    on_complete = function(response)
      cleanup()

      if not response or response == "" then
        vim.notify("[sade] No response from agent", vim.log.levels.WARN)
        return
      end

      -- Replace the selection with the response
      local lines = vim.split(response, "\n", { plain = true })

      vim.api.nvim_buf_set_text(
        sel.bufnr,
        sel.start_row,
        sel.start_col,
        sel.end_row,
        sel.end_col,
        lines
      )

      log.info("Visual replacement complete", { lines = #lines })
    end,
    on_error = function(err)
      cleanup()
      vim.notify("[sade] Error: " .. err, vim.log.levels.ERROR)
    end,
  })
end

-- Module exports
return {
  run_visual = run_visual,
  get_visual_selection = get_visual_selection,
}
