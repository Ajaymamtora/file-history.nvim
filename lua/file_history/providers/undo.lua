--- Undo tree provider for file history
--- Exposes Neovim's undo tree as a history source

local dbg = require("file_history.debug")

local M = {}

local function format_time_ago(timestamp)
  local now = os.time()
  local diff = now - timestamp

  if diff < 60 then
    return diff .. " seconds ago"
  elseif diff < 3600 then
    local mins = math.floor(diff / 60)
    return mins .. (mins == 1 and " minute ago" or " minutes ago")
  elseif diff < 86400 then
    local hours = math.floor(diff / 3600)
    return hours .. (hours == 1 and " hour ago" or " hours ago")
  elseif diff < 604800 then
    local days = math.floor(diff / 86400)
    return days .. (days == 1 and " day ago" or " days ago")
  elseif diff < 2592000 then
    local weeks = math.floor(diff / 604800)
    return weeks .. (weeks == 1 and " week ago" or " weeks ago")
  else
    local months = math.floor(diff / 2592000)
    return months .. (months == 1 and " month ago" or " months ago")
  end
end

local function traverse_undo_tree(entries, depth, result, max_entries)
  for _, entry in ipairs(entries or {}) do
    if max_entries > 0 and #result >= max_entries then
      return
    end

    if entry.alt then
      traverse_undo_tree(entry.alt, depth + 1, result, max_entries)
    end

    table.insert(result, {
      seq = entry.seq,
      timestamp = entry.time,
      is_save_point = entry.save ~= nil,
      branch_depth = depth,
      is_current = entry.curhead == true,
    })
  end
end

---@param buf number
---@param filepath string
---@return HistoryItem[]
function M.get_history(buf, filepath)
  if not vim.api.nvim_buf_is_valid(buf) then
    dbg.warn("undo_provider", "Invalid buffer", { buf = buf })
    return {}
  end

  local tree = vim.fn.undotree(buf)
  if not tree or not tree.entries or #tree.entries == 0 then
    dbg.debug("undo_provider", "No undo history", { buf = buf })
    return {}
  end

  local raw_items = {}
  local max_entries = M.config and M.config.max_entries or 100
  traverse_undo_tree(tree.entries, 0, raw_items, max_entries)

  local items = {}
  local save_points_only = M.config and M.config.save_points_only or false
  local include_branches = M.config and M.config.include_branches
  if include_branches == nil then
    include_branches = true
  end

  for _, raw in ipairs(raw_items) do
    local include = true

    if save_points_only and not raw.is_save_point then
      include = false
    end

    if not include_branches and raw.branch_depth > 0 then
      include = false
    end

    if include then
      local time_ago = format_time_ago(raw.timestamp)
      local date_str = os.date("%Y-%m-%d %H:%M:%S", raw.timestamp)
      local label = ""
      if raw.is_save_point then
        label = "[saved]"
      end
      if raw.is_current then
        label = label .. " [current]"
      end

      table.insert(items, {
        source = "undo",
        id = tostring(raw.seq),
        seq = raw.seq,
        timestamp = raw.timestamp,
        time_ago = time_ago,
        date = date_str,
        label = label:match("^%s*(.-)%s*$"),
        is_save_point = raw.is_save_point,
        branch_depth = raw.branch_depth,
        text = string.format("undo #%d %s", raw.seq, time_ago),
        buf = buf,
        file = filepath,
      })
    end
  end

  table.sort(items, function(a, b)
    return a.seq > b.seq
  end)

  dbg.debug("undo_provider", "Retrieved undo history", {
    buf = buf,
    total_entries = #tree.entries,
    returned = #items,
  })

  return items
end

---@param item HistoryItem
---@return string[]
function M.get_content(item)
  local buf = item.buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    dbg.warn("undo_provider", "Invalid buffer for content retrieval", { buf = buf })
    return {}
  end

  local tmp_file = vim.fn.stdpath("cache") .. "/file-history-undo-" .. buf
  local tmp_undo = tmp_file .. ".undo"

  local current_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  vim.fn.writefile(current_lines, tmp_file)

  local tmpbuf = vim.fn.bufadd(tmp_file)
  vim.bo[tmpbuf].swapfile = false
  vim.fn.bufload(tmpbuf)

  vim.api.nvim_buf_call(buf, function()
    pcall(vim.cmd, "silent wundo! " .. vim.fn.fnameescape(tmp_undo))
  end)

  vim.api.nvim_buf_call(tmpbuf, function()
    pcall(vim.cmd, "silent rundo " .. vim.fn.fnameescape(tmp_undo))
  end)

  local lines = {}
  local saved_ei = vim.o.eventignore
  vim.o.eventignore = "all"

  vim.api.nvim_buf_call(tmpbuf, function()
    local ok = pcall(vim.cmd, "silent undo " .. item.seq)
    if ok then
      lines = vim.api.nvim_buf_get_lines(tmpbuf, 0, -1, false)
    else
      dbg.warn("undo_provider", "Failed to navigate to undo state", { seq = item.seq })
    end
  end)

  vim.o.eventignore = saved_ei

  pcall(vim.api.nvim_buf_delete, tmpbuf, { force = true })
  pcall(vim.fn.delete, tmp_file)
  pcall(vim.fn.delete, tmp_undo)

  dbg.debug("undo_provider", "Retrieved content at undo state", {
    seq = item.seq,
    lines = #lines,
  })

  return lines
end

---@param item HistoryItem
---@return boolean
function M.can_revert(item)
  return item.seq ~= nil and item.buf ~= nil and vim.api.nvim_buf_is_valid(item.buf)
end

---@param item HistoryItem
---@param buf number
---@return boolean
function M.revert(item, buf)
  if not M.can_revert(item) then
    return false
  end

  local target_buf = item.buf or buf
  if not vim.api.nvim_buf_is_valid(target_buf) then
    return false
  end

  vim.api.nvim_buf_call(target_buf, function()
    vim.cmd("silent undo " .. item.seq)
  end)

  dbg.info("undo_provider", "Reverted to undo state", { seq = item.seq })
  return true
end

---@param action string
---@return boolean
function M.supports_action(action)
  local supported = {
    revert = true,
    open_tab = true,
    diff = true,
    yank_additions = true,
    yank_deletions = true,
    delete_history = false,
    purge_history = false,
  }
  return supported[action] == true
end

M.config = {
  include_branches = true,
  save_points_only = false,
  max_entries = 100,
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

return M
