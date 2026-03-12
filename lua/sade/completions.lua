--- Completion system for the prompt buffer.
--- Provides #node and @file completions (inspired by 99's completion system).
---
--- Usage in prompt buffer:
---   #heartbeat    → injects the heartbeat node contract
---   #skill        → injects SKILL.md
---   @lua/sade/init.lua → injects file content
---
--- Tokens are resolved at submit time: the prompt text is scanned for
--- #token and @token patterns, and their content is appended as references.

local log = require("sade.log")

local M = {}

--- Debounce interval for completion popup
local DEBOUNCE_MS = 100

--- Max file size to include (100KB)
local MAX_FILE_SIZE = 100 * 1024

--- Read a file's content, respecting max size.
---@param filepath string  absolute path
---@return string|nil content
local function read_file(filepath)
  local stat = vim.uv.fs_stat(filepath)
  if not stat or stat.type ~= "file" then
    return nil
  end
  if stat.size > MAX_FILE_SIZE then
    return nil
  end
  local f = io.open(filepath, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  return content
end

--- Scan all .md files in .sade/ (root + nodes/) for # completion.
--- Returns items sorted with nodes first, then root-level .md files.
---@return { name: string, description: string, path: string }[]
local function get_node_items()
  local sade = package.loaded["sade"]
  if not sade or not sade.state then
    return {}
  end

  local sade_root = sade.state.sade_root
  local idx = sade.state.index
  local items = {}
  local seen = {}

  -- 1. Add all node .md files (with description from index if available)
  local nodes_dir = sade_root .. "/nodes"
  local handle = vim.uv.fs_scandir(nodes_dir)
  if handle then
    while true do
      local name, typ = vim.uv.fs_scandir_next(handle)
      if not name then break end
      if typ == "file" and name:match("%.md$") then
        local id = name:gsub("%.md$", "")
        local node = idx and idx.nodes[id] or nil
        local desc = node and node.description or "(node)"
        table.insert(items, {
          name = id,
          description = desc,
          path = nodes_dir .. "/" .. name,
        })
        seen[id] = true
      end
    end
  end

  -- 2. Add root-level .sade/*.md files (SKILL.md, README.md, etc.)
  handle = vim.uv.fs_scandir(sade_root)
  if handle then
    while true do
      local name, typ = vim.uv.fs_scandir_next(handle)
      if not name then break end
      if typ == "file" and name:match("%.md$") then
        local id = name:gsub("%.md$", ""):lower()
        if not seen[id] then
          -- Read first non-empty line as description
          local f = io.open(sade_root .. "/" .. name, "r")
          local desc = name
          if f then
            for line in f:lines() do
              local trimmed = vim.trim(line):gsub("^#+%s*", "")
              if trimmed ~= "" then
                desc = trimmed
                break
              end
            end
            f:close()
          end
          table.insert(items, {
            name = id,
            description = desc,
            path = sade_root .. "/" .. name,
          })
          seen[id] = true
        end
      end
    end
  end

  table.sort(items, function(a, b) return a.name < b.name end)
  return items
end

--- Resolve a #token to its content.
--- Looks up .sade/nodes/<token>.md first, then .sade/<token>.md (case-insensitive).
---@param token string  e.g. "heartbeat", "skill", "readme"
---@return string|nil content
function M.resolve_node(token)
  local sade = package.loaded["sade"]
  if not sade or not sade.state then
    return nil
  end

  local sade_root = sade.state.sade_root

  -- Try as a node file first
  local node_file = sade_root .. "/nodes/" .. token .. ".md"
  local content = read_file(node_file)
  if content then
    return content
  end

  -- Try as a root-level .sade/*.md (case-insensitive match)
  local handle = vim.uv.fs_scandir(sade_root)
  if handle then
    while true do
      local name, typ = vim.uv.fs_scandir_next(handle)
      if not name then break end
      if typ == "file" and name:match("%.md$") then
        local id = name:gsub("%.md$", ""):lower()
        if id == token:lower() then
          return read_file(sade_root .. "/" .. name)
        end
      end
    end
  end

  return nil
end

--- Get all project files for @file completion.
---@return { path: string, name: string, absolute_path: string }[]
local function get_file_items()
  local sade = package.loaded["sade"]
  if not sade or not sade.state then
    return {}
  end

  local project_root = sade.state.project_root
  local items = {}

  -- Use git ls-files for fast file discovery
  local handle = io.popen("cd " .. vim.fn.shellescape(project_root) .. " && git ls-files 2>/dev/null")
  if handle then
    for line in handle:lines() do
      local name = line:match("([^/]+)$") or line
      table.insert(items, {
        path = line,
        name = name,
        absolute_path = project_root .. "/" .. line,
      })
    end
    handle:close()
  end

  -- Fallback: scan filesystem if git not available
  if #items == 0 then
    local skip = { [".git"] = true, [".sade"] = true, ["node_modules"] = true, [".next"] = true, ["dist"] = true, ["build"] = true }
    local function scan(dir, prefix)
      local h = vim.uv.fs_scandir(dir)
      if not h then return end
      while true do
        local fname, typ = vim.uv.fs_scandir_next(h)
        if not fname then break end
        if not fname:match("^%.") then
          local rel = prefix == "" and fname or (prefix .. "/" .. fname)
          if typ == "directory" and not skip[fname] then
            scan(dir .. "/" .. fname, rel)
          elseif typ == "file" then
            table.insert(items, {
              path = rel,
              name = fname,
              absolute_path = dir .. "/" .. fname,
            })
          end
        end
      end
    end
    scan(project_root, "")
  end

  table.sort(items, function(a, b) return a.path < b.path end)
  return items
end

--- Resolve a @token to its content.
---@param token string  relative file path, e.g. "lua/sade/init.lua"
---@return string|nil content
function M.resolve_file(token)
  local sade = package.loaded["sade"]
  if not sade or not sade.state then
    return nil
  end

  local project_root = sade.state.project_root
  local abs = project_root .. "/" .. token
  local content = read_file(abs)
  if not content then
    return nil
  end

  local ext = token:match("%.([^%.]+)$") or ""
  return string.format("```%s\n-- %s\n%s\n```", ext, token, content)
end

--- Parse prompt text and resolve all #node and @file references.
--- Returns the original prompt with references appended as context blocks.
---@param prompt_text string
---@return string resolved_prompt
function M.resolve_prompt(prompt_text)
  local refs = {}

  -- Parse #node references
  for token in prompt_text:gmatch("#(%S+)") do
    -- Skip markdown headers (## or ### etc.)
    if not token:match("^#") then
      local content = M.resolve_node(token)
      if content then
        table.insert(refs, {
          label = "#" .. token,
          content = content,
        })
      end
    end
  end

  -- Parse @file references
  for token in prompt_text:gmatch("@(%S+)") do
    local content = M.resolve_file(token)
    if content then
      table.insert(refs, {
        label = "@" .. token,
        content = content,
      })
    end
  end

  if #refs == 0 then
    return prompt_text
  end

  -- Append resolved references
  local parts = { prompt_text, "\n\n---\n\n# References\n" }
  for _, ref in ipairs(refs) do
    table.insert(parts, "\n## " .. ref.label .. "\n\n" .. ref.content .. "\n")
  end

  return table.concat(parts)
end

--- Set up native completion for a prompt buffer.
--- Triggers completion popup when user types # or @.
---@param bufnr number  the prompt buffer
function M.attach(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local timer = vim.uv.new_timer()
  local group = vim.api.nvim_create_augroup("sade_completions_" .. bufnr, { clear = true })

  vim.api.nvim_create_autocmd("TextChangedI", {
    group = group,
    buffer = bufnr,
    callback = function()
      timer:stop()
      timer:start(DEBOUNCE_MS, 0, vim.schedule_wrap(function()
        if vim.fn.mode() ~= "i" then
          return
        end
        if not vim.api.nvim_buf_is_valid(bufnr) then
          timer:stop()
          return
        end

        local line = vim.api.nvim_get_current_line()
        local col = vim.fn.col(".")
        local before = line:sub(1, col - 1)

        -- Check for #token trigger
        local hash_start = before:match(".*()#%S*$")
        if hash_start then
          local partial = before:sub(hash_start + 1) -- includes #
          local query = partial:sub(2):lower()        -- without #

          local items = {}
          for _, item in ipairs(get_node_items()) do
            if query == "" or item.name:lower():find(query, 1, true) then
              table.insert(items, {
                word = "#" .. item.name,
                abbr = "#" .. item.name,
                info = item.description,
                icase = 1,
                dup = 0,
              })
            end
          end

          if #items > 0 then
            vim.fn.complete(hash_start, items)
          end
          return
        end

        -- Check for @token trigger
        local at_start = before:match(".*()@%S*$")
        if at_start then
          local partial = before:sub(at_start + 1) -- includes @
          local query = partial:sub(2):lower()      -- without @

          local items = {}
          for _, item in ipairs(get_file_items()) do
            -- Fuzzy match: all query chars must appear in order
            local searchable = (item.name .. " " .. item.path):lower()
            local match_pos = 1
            local matched = true
            for i = 1, #query do
              local char = query:sub(i, i)
              local found = searchable:find(char, match_pos, true)
              if not found then
                matched = false
                break
              end
              match_pos = found + 1
            end

            if matched then
              table.insert(items, {
                word = "@" .. item.path,
                abbr = "@" .. item.name,
                info = item.path,
                icase = 1,
                dup = 0,
              })
            end
          end

          if #items > 0 then
            vim.fn.complete(at_start, items)
          end
          return
        end
      end))
    end,
  })

  -- Tab / Shift-Tab to navigate completion menu
  vim.keymap.set("i", "<Tab>", function()
    if vim.fn.pumvisible() == 1 then
      return "<C-n>"
    end
    return "<Tab>"
  end, { buffer = bufnr, expr = true, noremap = true })

  vim.keymap.set("i", "<S-Tab>", function()
    if vim.fn.pumvisible() == 1 then
      return "<C-p>"
    end
    return "<S-Tab>"
  end, { buffer = bufnr, expr = true, noremap = true })

  -- Clean up on buffer wipe
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = bufnr,
    callback = function()
      timer:stop()
      timer:close()
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })

  -- Enable fuzzy completion
  vim.api.nvim_set_option_value("completeopt", "menuone,noinsert,noselect,popup,fuzzy", { buf = bufnr })

  log.debug("Completions attached to buffer", { bufnr = bufnr })
end

return M
