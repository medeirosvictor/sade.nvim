--- Search operation: semantic search scoped to node context.
--- Agent scans the codebase and returns locations as a quickfix list.

local log = require("sade.log")

local M = {}

--- Search prompt template.
--- Instructs the agent to return locations in quickfix-compatible format.
local SEARCH_PROMPT = [[
You are given a project with an architectural description and a search query.
Search through the codebase and return ALL relevant code locations that match the query.

<OutputFormat>
/absolute/path/to/file.ext:LNUM:COL,LINES,NOTES
</OutputFormat>

<Rules>
- LNUM = starting line number (1-based)
- COL = starting column number (1-based)
- LINES = how many lines to highlight (minimum 1)
- NOTES = a brief description of why this location is relevant (no newlines)
- Each location on its own line
- Use absolute paths
- Output ONLY locations, no commentary or explanation
- Double check the format before responding
</Rules>

<Example>
/home/user/project/src/auth.lua:24:1,3,Handles JWT token validation
/home/user/project/src/middleware.lua:71:5,7,Auth middleware that checks session
/home/user/project/src/routes/login.lua:13:1,12,Login endpoint handler
</Example>

Do NOT modify any files. Only search and report locations.
]]

--- Parse a single line of agent output into a quickfix entry.
---@param line string
---@return { filename: string, lnum: number, col: number, text: string }|nil
local function parse_qf_line(line)
  -- Format: /path/to/file.ext:LNUM:COL,LINES,NOTES
  local filepath, lnum_raw, rest = line:match("^(.-):([^:]+):(.+)$")
  if not filepath or not lnum_raw or not rest then
    return nil
  end

  -- rest = "COL,LINES,NOTES"
  local col_raw, _, notes = rest:match("^([^,]+),([^,]+),?(.*)$")
  if not col_raw then
    return nil
  end

  local lnum = tonumber(lnum_raw) or 1
  local col = tonumber(col_raw) or 1

  -- Validate: must be a real-looking path
  if not filepath:match("^/") and not filepath:match("^%a:") then
    return nil
  end

  return {
    filename = filepath,
    lnum = lnum,
    col = col,
    text = notes or "",
  }
end

--- Parse agent response into quickfix entries.
---@param response string
---@return { filename: string, lnum: number, col: number, text: string }[]
function M.parse_response(response)
  if not response or response == "" then
    return {}
  end

  local entries = {}
  for line in response:gmatch("[^\n]+") do
    line = vim.trim(line)
    -- Skip empty lines and commentary
    if line ~= "" and not line:match("^%s*$") then
      local entry = parse_qf_line(line)
      if entry then
        table.insert(entries, entry)
      end
    end
  end
  return entries
end

--- Set the quickfix list and open the quickfix window.
---@param entries { filename: string, lnum: number, col: number, text: string }[]
---@param title string
function M.set_qflist(entries, title)
  if #entries == 0 then
    vim.notify("[sade] No search results found", vim.log.levels.INFO)
    return
  end

  vim.fn.setqflist({}, "r", {
    title = title,
    items = entries,
  })
  vim.cmd("copen")
  vim.notify(("[sade] Found %d location(s)"):format(#entries))
end

--- Build the full search prompt with node context.
---@param sade_root string
---@param idx SadeIndex
---@param query string  the user's search query
---@param node_ids string[]  nodes to scope the search to
---@return string prompt
function M.build_prompt(sade_root, idx, query, node_ids)
  local parts = {}

  -- Add search instruction
  table.insert(parts, SEARCH_PROMPT)

  -- Add node context if available
  if #node_ids > 0 then
    table.insert(parts, "\n<Scope>")
    table.insert(parts, "Focus your search on files belonging to these architectural nodes:")
    for _, nid in ipairs(node_ids) do
      local node = idx.nodes[nid]
      if node then
        table.insert(parts, "\n### Node: " .. nid)
        if node.description then
          table.insert(parts, node.description)
        end
        -- List files in this node
        local files = {}
        for filepath, fnode_ids in pairs(idx.file_to_nodes) do
          for _, fid in ipairs(fnode_ids) do
            if fid == nid then
              table.insert(files, filepath)
              break
            end
          end
        end
        table.sort(files)
        if #files > 0 then
          table.insert(parts, "Files:")
          for _, f in ipairs(files) do
            table.insert(parts, "- " .. f)
          end
        end
      end
    end
    table.insert(parts, "</Scope>")
  else
    table.insert(parts, "\n<Scope>Search the entire project.</Scope>")
  end

  -- Add the user query
  table.insert(parts, "\n<SearchQuery>")
  table.insert(parts, query)
  table.insert(parts, "</SearchQuery>")

  return table.concat(parts, "\n")
end

--- Run a search: open prompt, invoke agent, parse results to quickfix.
---@param sade_root string
---@param idx SadeIndex
---@param opts? { node_ids?: string[] }
function M.run(sade_root, idx, opts)
  opts = opts or {}
  log.set_area("search")

  -- Determine scope from current file or explicit node_ids
  local node_ids = opts.node_ids or {}
  if #node_ids == 0 then
    local buf_path = vim.api.nvim_buf_get_name(0)
    if buf_path ~= "" then
      local index = require("sade.index")
      node_ids = index.query(idx, buf_path)
    end
  end

  local scope_label = #node_ids > 0
    and ("nodes: " .. table.concat(node_ids, ", "))
    or "entire project"

  -- Open prompt to get the search query
  local prompt_mod = require("sade.prompt")

  prompt_mod.open({
    title = "SADE · Search (" .. scope_label .. ")",
    default_text = "",
    on_submit = function(query)
      log.info("Search invoked", { query = query, nodes = node_ids })

      local full_prompt = M.build_prompt(sade_root, idx, query, node_ids)

      -- Show loading indicator
      prompt_mod.show_message({
        title = "🔍 Searching...",
        content = { "⏳ Agent is searching the codebase..." },
        position = "top-right",
      })

      local agent = require("sade.agent")
      agent.invoke(sade_root, idx, {
        prompt = full_prompt,
        on_complete = function(response)
          -- Strip escape codes
          if response then
            response = response:gsub("\27%][^\7]*\7", "")
            response = response:gsub("\27%[[%d;]*[a-zA-Z]", "")
            response = vim.trim(response)
          end

          log.info("Search response received", { resp_len = response and #response or 0 })

          -- Close loading indicator
          prompt_mod.close_message()

          -- Parse and set quickfix
          local entries = M.parse_response(response)
          M.set_qflist(entries, "SADE Search: " .. query)
        end,
        on_error = function(err)
          prompt_mod.close_message()
          log.error("Search failed", { err = err })
          vim.notify("[sade] Search failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
        end,
      })
    end,
    on_cancel = function() end,
  })
end

return M
