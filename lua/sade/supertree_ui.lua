local M = {}

local config = require("sade.config")
local supertree = require("sade.supertree")
local heartbeat = require("sade.heartbeat")
local log = require("sade.log")

---@class SuperTreeUI
local ui = {
  bufnr = nil,              -- tree buffer
  winnr = nil,              -- tree window
  expanded = {},            -- node_id → boolean
  entries = {},             -- current rendered entries
  idx = nil,                -- SadeIndex reference
  refresh_timer = nil,      -- heartbeat refresh timer
  showing_response = false, -- true when agent response is displayed
}

-- Expose entries for node_actions
M.entries = ui.entries

--- Check if a window is a regular editor window (not a sidebar).
---@param w number window id
---@return boolean
local function is_editor_win(w)
  if not w or w == 0 or not vim.api.nvim_win_is_valid(w) then
    return false
  end
  if w == ui.winnr then
    return false
  end
  local buf = vim.api.nvim_win_get_buf(w)
  local ft = vim.bo[buf].filetype
  if ft == "NvimTree" or ft == "sade_tree" or ft == "neo-tree" then
    return false
  end
  return true
end

--- Find the best editor window to open a file in.
---@return number|nil window id
local function find_editor_win()
  local prev_win = vim.fn.win_getid(vim.fn.winnr("#"))
  if is_editor_win(prev_win) then
    return prev_win
  end
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if is_editor_win(w) then
      return w
    end
  end
  return nil
end

--- Open a file in the best available editor window, or create a split.
---@param filepath string
local function open_in_editor(filepath)
  local win = find_editor_win()
  if win then
    vim.api.nvim_set_current_win(win)
    vim.cmd("edit " .. vim.fn.fnameescape(filepath))
  else
    vim.cmd("belowright vsplit " .. vim.fn.fnameescape(filepath))
  end
end

local ICONS = {
  node_open = "▼ ",
  node_closed = "▶ ",
  file = "  ",
  active = "● ",
  unmapped = "? ",
}

--- Render a single entry into a display line.
---@param entry SuperTreeEntry
---@return string
local function render_line(entry)
  local indent = string.rep("  ", entry.depth)
  local prefix = ""
  local suffix = ""

  if entry.type == "header" or entry.type == "separator" or entry.type == "legend" then
    return entry.label
  elseif entry.type == "node" or entry.type == "unmapped_header" then
    if entry.active then
      prefix = ICONS.active
    elseif entry.reading then
      prefix = "◇ "
    elseif entry.stale then
      prefix = ICONS.active
    else
      prefix = entry.expanded and ICONS.node_open or ICONS.node_closed
    end
    suffix = "  (" .. (entry.file_count or 0) .. ")"
  elseif entry.type == "file" or entry.type == "unmapped_file" then
    if entry.active or entry.stale then
      prefix = ICONS.active
    elseif entry.reading then
      prefix = "◇ "
    else
      prefix = ICONS.file
    end
  end

  return indent .. prefix .. entry.label .. suffix
end

--- Apply highlights to the tree buffer.
---@param bufnr number
---@param entries SuperTreeEntry[]
local function apply_highlights(bufnr, entries)
  local ok, err = pcall(function()
    local ns = vim.api.nvim_create_namespace("sade_supertree_hl")
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

    for i, entry in ipairs(entries) do
      local line = i - 1
      if entry.type == "header" then
        vim.api.nvim_buf_add_highlight(bufnr, ns, "Title", line, 0, -1)
      elseif entry.type == "separator" or entry.type == "legend" then
        vim.api.nvim_buf_add_highlight(bufnr, ns, "Comment", line, 0, -1)
      elseif entry.type == "agent_running" then
        vim.api.nvim_buf_add_highlight(bufnr, ns, "DiagnosticWarn", line, 0, -1)
      elseif entry.active then
        vim.api.nvim_buf_add_highlight(bufnr, ns, "DiagnosticWarn", line, 0, -1)
      elseif entry.reading then
        vim.api.nvim_buf_add_highlight(bufnr, ns, "DiagnosticInfo", line, 0, -1)
      elseif entry.stale then
        vim.api.nvim_buf_add_highlight(bufnr, ns, "DiagnosticHint", line, 0, -1)
      elseif entry.type == "node" then
        vim.api.nvim_buf_add_highlight(bufnr, ns, "Title", line, 0, -1)
      elseif entry.type == "unmapped_header" then
        vim.api.nvim_buf_add_highlight(bufnr, ns, "Comment", line, 0, -1)
      elseif entry.type == "unmapped_file" then
        vim.api.nvim_buf_add_highlight(bufnr, ns, "Comment", line, 0, -1)
      end
    end
  end)
  if not ok then
    log.error("apply_highlights failed", { error = tostring(err) })
  end
end

--- Render the tree into the buffer.
local function render()
  local ok, err = pcall(function()
    if not ui.bufnr or not vim.api.nvim_buf_is_valid(ui.bufnr) then
      return
    end

    -- always use the current index from sade.state (supports live updates)
    local sade = require("sade")
    if not sade.state or not sade.state.index then
      return
    end

    -- check if agent is running
    local agent_running = sade.state and sade.state.agent_running or nil

    local new_entries = supertree.build_entries(sade.state.index, ui.expanded, agent_running)
    ui.entries = new_entries
    M.entries = new_entries

    local lines = {}
    for _, entry in ipairs(ui.entries) do
      table.insert(lines, render_line(entry))
    end

    vim.bo[ui.bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(ui.bufnr, 0, -1, false, lines)
    vim.bo[ui.bufnr].modifiable = false

    apply_highlights(ui.bufnr, ui.entries)
  end)
  if not ok then
    vim.notify("[sade] render error: " .. tostring(err), vim.log.levels.ERROR)
  end
end

--- Toggle expand/collapse for the entry under cursor.
local function toggle_entry()
  local cursor = vim.api.nvim_win_get_cursor(ui.winnr)
  local row = cursor[1]
  local entry = ui.entries[row]
  if not entry then
    return
  end

  if entry.type == "node" then
    ui.expanded[entry.id] = not ui.expanded[entry.id]
    render()
  elseif entry.type == "unmapped_header" then
    ui.expanded["__unmapped__"] = not ui.expanded["__unmapped__"]
    render()
  elseif entry.type == "file" or entry.type == "unmapped_file" then
    if entry.filepath then
      open_in_editor(entry.filepath)
    end
  end
end

--- Open the node's markdown file in an editor buffer.
local function edit_entry()
  local cursor = vim.api.nvim_win_get_cursor(ui.winnr)
  local entry = ui.entries[cursor[1]]
  if not entry or entry.type ~= "node" then
    return
  end

  local sade = require("sade")
  if not sade.state then
    vim.notify("[sade] not initialized", vim.log.levels.WARN)
    return
  end

  local node_file = sade.state.sade_root .. "/nodes/" .. entry.id .. ".md"
  open_in_editor(node_file)
end

--- Start periodic refresh for heartbeat state.
local function start_refresh()
  if ui.refresh_timer then
    return
  end
  ui.refresh_timer = vim.uv.new_timer()
  ui.refresh_timer:start(0, 500, function()
    vim.schedule(function()
      if ui.bufnr and vim.api.nvim_buf_is_valid(ui.bufnr) then
        render()
      else
        M.close()
      end
    end)
  end)
end

--- Stop periodic refresh.
local function stop_refresh()
  if ui.refresh_timer then
    ui.refresh_timer:stop()
    ui.refresh_timer:close()
    ui.refresh_timer = nil
  end
end

--- Create the tree buffer and window.
---@param idx SadeIndex
function M.open(idx)
  -- if already open, focus it
  if ui.winnr and vim.api.nvim_win_is_valid(ui.winnr) then
    vim.api.nvim_set_current_win(ui.winnr)
    return
  end

  ui.idx = idx

  -- create buffer
  ui.bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[ui.bufnr].buftype = "nofile"
  vim.bo[ui.bufnr].bufhidden = "wipe"
  vim.bo[ui.bufnr].swapfile = false
  vim.bo[ui.bufnr].filetype = "sade_tree"

  -- open as side split
  local tree_config = config.values.tree
  local pos = tree_config.side == "right" and "botright" or "topleft"
  vim.cmd(pos .. " vertical " .. tree_config.width .. "split")
  ui.winnr = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(ui.winnr, ui.bufnr)

  -- window options
  vim.wo[ui.winnr].number = false
  vim.wo[ui.winnr].relativenumber = false
  vim.wo[ui.winnr].signcolumn = "no"
  vim.wo[ui.winnr].foldcolumn = "0"
  vim.wo[ui.winnr].wrap = false
  vim.wo[ui.winnr].cursorline = true
  vim.wo[ui.winnr].winfixwidth = true  -- prevent auto-resize when other windows open/close

  -- keymaps
  local opts = { buffer = ui.bufnr, silent = true }
  vim.keymap.set("n", "<CR>", toggle_entry, opts)
  vim.keymap.set("n", "o", toggle_entry, opts)
  vim.keymap.set("n", "K", edit_entry, opts)
  vim.keymap.set("n", "q", function()
    if ui.showing_response then
      M.dismiss_response()
    else
      M.close()
    end
  end, opts)
  vim.keymap.set("n", "<Esc>", function()
    if ui.showing_response then
      M.dismiss_response()
    end
  end, opts)
  vim.keymap.set("n", "R", function()
    if ui.showing_response then
      M.dismiss_response()
    else
      render()
    end
  end, opts)
  vim.keymap.set("n", "a", function()
    -- Just trigger SadePrompt which adapts to tree context
    vim.cmd("SadePrompt")
  end, opts)
  -- Node action keybinds
  vim.keymap.set("n", "i", function()
    local cursor = vim.api.nvim_win_get_cursor(ui.winnr)
    local entry = ui.entries[cursor[1]]
    if entry and entry.type == "node" and entry.id then
      local node_actions = require("sade.node_actions")
      node_actions.run_action("improve", entry.id, "node")
    end
  end, opts)
  vim.keymap.set("n", "c", function()
    local cursor = vim.api.nvim_win_get_cursor(ui.winnr)
    local entry = ui.entries[cursor[1]]
    if entry and entry.type == "node" and entry.id then
      local node_actions = require("sade.node_actions")
      node_actions.run_action("compact", entry.id, "node")
    end
  end, opts)

  render()
  start_refresh()

  -- cleanup on buffer wipe
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = ui.bufnr,
    once = true,
    callback = function()
      stop_refresh()
      ui.bufnr = nil
      ui.winnr = nil
    end,
  })
end

--- Close the tree window.
function M.close()
  stop_refresh()
  if ui.winnr and vim.api.nvim_win_is_valid(ui.winnr) then
    vim.api.nvim_win_close(ui.winnr, true)
  end
  ui.winnr = nil
  ui.bufnr = nil
end

--- Focus the tree: open if closed, focus if open but not active, close if focused.
---@param idx SadeIndex
function M.toggle(idx)
  if ui.winnr and vim.api.nvim_win_is_valid(ui.winnr) then
    if vim.api.nvim_get_current_win() == ui.winnr then
      M.close()
    else
      vim.api.nvim_set_current_win(ui.winnr)
    end
  else
    M.open(idx)
  end
end

--- Get the entry under cursor if the current window is the tree.
--- Returns nil if not in the tree window.
---@return SuperTreeEntry|nil
function M.get_cursor_entry()
  if not ui.winnr or not vim.api.nvim_win_is_valid(ui.winnr) then
    return nil
  end
  if vim.api.nvim_get_current_win() ~= ui.winnr then
    return nil
  end
  local cursor = vim.api.nvim_win_get_cursor(ui.winnr)
  return ui.entries[cursor[1]]
end

--- Refresh the tree: re-render with current index.
function M.refresh()
  -- don't refresh while showing a response
  if ui.showing_response then
    return
  end
  local ok, err = pcall(function()
    if ui.bufnr and vim.api.nvim_buf_is_valid(ui.bufnr) then
      render()
    end
  end)
  if not ok then
    vim.notify("[sade] tree refresh error: " .. tostring(err), vim.log.levels.ERROR)
  end
end

--- Show agent response inline in the tree buffer.
--- Replaces tree content temporarily. Press q/R/Esc to go back.
---@param response string  agent response text
---@param context? string  what was asked about (e.g., "node heartbeat")
function M.show_response(response, context)
  log.info("show_response called", { bufnr = ui.bufnr, winnr = ui.winnr })
  if not ui.bufnr or not vim.api.nvim_buf_is_valid(ui.bufnr) then
    log.info("show_response: buffer invalid", { bufnr = ui.bufnr })
    return
  end
  if not ui.winnr or not vim.api.nvim_win_is_valid(ui.winnr) then
    log.info("show_response: window invalid", { winnr = ui.winnr })
    return
  end

  ui.showing_response = true

  -- build display lines
  local lines = {}
  local width = vim.api.nvim_win_get_width(ui.winnr) - 2

  table.insert(lines, " Agent Response")
  if context then
    table.insert(lines, " " .. context)
  end
  table.insert(lines, string.rep("─", width))
  table.insert(lines, "")

  -- wrap response text to fit the tree width
  for resp_line in response:gmatch("[^\n]*") do
    if resp_line == "" then
      table.insert(lines, "")
    else
      -- simple word wrap
      while #resp_line > width do
        local break_at = resp_line:sub(1, width):match(".*()%s") or width
        table.insert(lines, resp_line:sub(1, break_at))
        resp_line = resp_line:sub(break_at + 1)
      end
      if resp_line ~= "" then
        table.insert(lines, resp_line)
      end
    end
  end

  table.insert(lines, "")
  table.insert(lines, string.rep("─", width))
  table.insert(lines, " press R to return to tree")

  -- render into buffer
  vim.bo[ui.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(ui.bufnr, 0, -1, false, lines)
  vim.bo[ui.bufnr].modifiable = false

  -- apply highlights
  local ns = vim.api.nvim_create_namespace("sade_supertree_hl")
  vim.api.nvim_buf_clear_namespace(ui.bufnr, ns, 0, -1)
  -- header
  vim.api.nvim_buf_add_highlight(ui.bufnr, ns, "Title", 0, 0, -1)
  if context then
    vim.api.nvim_buf_add_highlight(ui.bufnr, ns, "Comment", 1, 0, -1)
  end
  -- footer hint
  vim.api.nvim_buf_add_highlight(ui.bufnr, ns, "Comment", #lines - 1, 0, -1)

  log.info("show_response: rendered", { line_count = #lines })
end

--- Dismiss response view and return to the tree.
function M.dismiss_response()
  ui.showing_response = false
  render()
end

return M
