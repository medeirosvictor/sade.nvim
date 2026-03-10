--- Shared UI primitives for SADE popups.
local M = {}

--- Open a centered floating window with content.
---@param lines string[]          content lines
---@param opts? { title?: string, width?: number, height?: number, ft?: string, on_key?: table<string, fun()> }
---@return number bufnr, number winnr
function M.popup(lines, opts)
  opts = opts or {}

  local max_width = 0
  for _, l in ipairs(lines) do
    max_width = math.max(max_width, vim.fn.strdisplaywidth(l))
  end

  local width = opts.width or math.min(max_width + 4, math.floor(vim.o.columns * 0.8))
  local height = opts.height or math.min(#lines + 2, math.floor(vim.o.lines * 0.8))

  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  if opts.ft then
    vim.bo[buf].filetype = opts.ft
  end

  local win_opts = {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
  }
  if opts.title then
    win_opts.title = " " .. opts.title .. " "
    win_opts.title_pos = "center"
  end

  local win = vim.api.nvim_open_win(buf, true, win_opts)
  vim.wo[win].cursorline = true
  vim.wo[win].wrap = true

  -- close on q/Esc
  local close = function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  vim.keymap.set("n", "q", close, { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, silent = true })

  -- custom keymaps
  if opts.on_key then
    for key, fn in pairs(opts.on_key) do
      vim.keymap.set("n", key, function()
        fn()
        close()
      end, { buffer = buf, silent = true })
    end
  end

  return buf, win
end

--- Open a selection popup — items with a callback on Enter.
---@param title string
---@param items { label: string, value: any }[]
---@param on_select fun(item: { label: string, value: any })
function M.select(title, items, on_select)
  local lines = {}
  for i, item in ipairs(items) do
    table.insert(lines, ("  %d. %s"):format(i, item.label))
  end

  -- add padding
  table.insert(lines, 1, "")
  table.insert(lines, "")
  table.insert(lines, "  Press Enter to select, q/Esc to cancel")

  local buf, win = M.popup(lines, { title = title })

  -- place cursor on first item
  vim.api.nvim_win_set_cursor(win, { 2, 0 })

  vim.keymap.set("n", "<CR>", function()
    local cursor = vim.api.nvim_win_get_cursor(win)
    local row = cursor[1]
    local idx = row - 1 -- offset for top padding
    if idx >= 1 and idx <= #items then
      vim.api.nvim_win_close(win, true)
      on_select(items[idx])
    end
  end, { buffer = buf, silent = true })

  -- number keys for quick selection
  for i, item in ipairs(items) do
    if i <= 9 then
      vim.keymap.set("n", tostring(i), function()
        vim.api.nvim_win_close(win, true)
        on_select(item)
      end, { buffer = buf, silent = true })
    end
  end
end

return M
