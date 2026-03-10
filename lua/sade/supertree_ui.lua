local M = {}

local config = require("sade.config")
local supertree = require("sade.supertree")
local heartbeat = require("sade.heartbeat")

---@class SuperTreeUI
local ui = {
  bufnr = nil,           -- tree buffer
  winnr = nil,           -- tree window
  expanded = {},         -- node_id → boolean
  entries = {},          -- current rendered entries
  idx = nil,             -- SadeIndex reference
  refresh_timer = nil,   -- heartbeat refresh timer
}

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

  if entry.type == "node" or entry.type == "unmapped_header" then
    prefix = entry.expanded and ICONS.node_open or ICONS.node_closed
    if entry.active then
      prefix = ICONS.active .. prefix
    end
    suffix = "  (" .. (entry.file_count or 0) .. ")"
  elseif entry.type == "file" or entry.type == "unmapped_file" then
    if entry.active then
      prefix = ICONS.active
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
  local ns = vim.api.nvim_create_namespace("sade_supertree_hl")
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  for i, entry in ipairs(entries) do
    local line = i - 1
    if entry.active then
      vim.api.nvim_buf_add_highlight(bufnr, ns, "DiagnosticWarn", line, 0, -1)
    elseif entry.type == "node" then
      vim.api.nvim_buf_add_highlight(bufnr, ns, "Title", line, 0, -1)
    elseif entry.type == "unmapped_header" then
      vim.api.nvim_buf_add_highlight(bufnr, ns, "Comment", line, 0, -1)
    elseif entry.type == "unmapped_file" then
      vim.api.nvim_buf_add_highlight(bufnr, ns, "Comment", line, 0, -1)
    end
  end
end

--- Render the tree into the buffer.
local function render()
  if not ui.bufnr or not vim.api.nvim_buf_is_valid(ui.bufnr) then
    return
  end
  if not ui.idx then
    return
  end

  ui.entries = supertree.build_entries(ui.idx, ui.expanded)

  local lines = {}
  for _, entry in ipairs(ui.entries) do
    table.insert(lines, render_line(entry))
  end

  vim.bo[ui.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(ui.bufnr, 0, -1, false, lines)
  vim.bo[ui.bufnr].modifiable = false

  apply_highlights(ui.bufnr, ui.entries)
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
    -- open the file in the previous window
    if entry.filepath then
      local prev_win = vim.fn.win_getid(vim.fn.winnr("#"))
      if prev_win == 0 or not vim.api.nvim_win_is_valid(prev_win) then
        -- find first non-tree window
        for _, w in ipairs(vim.api.nvim_list_wins()) do
          if w ~= ui.winnr then
            prev_win = w
            break
          end
        end
      end
      if prev_win and prev_win ~= 0 then
        vim.api.nvim_set_current_win(prev_win)
        vim.cmd("edit " .. vim.fn.fnameescape(entry.filepath))
      end
    end
  end
end

--- Show node description in a floating preview.
local function preview_entry()
  local cursor = vim.api.nvim_win_get_cursor(ui.winnr)
  local entry = ui.entries[cursor[1]]
  if not entry or entry.type ~= "node" then
    return
  end

  local lines = { entry.label, string.rep("─", #entry.label) }
  if entry.description and entry.description ~= "" then
    for line in (entry.description .. "\n"):gmatch("([^\n]*)\n") do
      table.insert(lines, line)
    end
  end
  table.insert(lines, "")
  table.insert(lines, "Files: " .. (entry.file_count or 0))

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, #l)
  end

  vim.api.nvim_open_win(buf, false, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = math.min(width + 2, 60),
    height = #lines,
    style = "minimal",
    border = "rounded",
  })

  -- close on cursor move
  vim.api.nvim_create_autocmd({ "CursorMoved", "BufLeave" }, {
    buffer = ui.bufnr,
    once = true,
    callback = function()
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end,
  })
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

  -- keymaps
  local opts = { buffer = ui.bufnr, silent = true }
  vim.keymap.set("n", "<CR>", toggle_entry, opts)
  vim.keymap.set("n", "o", toggle_entry, opts)
  vim.keymap.set("n", "K", preview_entry, opts)
  vim.keymap.set("n", "q", function() M.close() end, opts)
  vim.keymap.set("n", "R", function() render() end, opts)

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

--- Toggle the tree open/closed.
---@param idx SadeIndex
function M.toggle(idx)
  if ui.winnr and vim.api.nvim_win_is_valid(ui.winnr) then
    M.close()
  else
    M.open(idx)
  end
end

return M
