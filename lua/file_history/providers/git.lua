--- Git provider for file history
--- Wraps existing fh.lua git operations with the provider interface

local dbg = require("file_history.debug")

local M = {}

---@type table Reference to fh module (lazy loaded)
local fh = nil

local function get_fh()
  if not fh then
    fh = require("file_history.fh")
  end
  return fh
end

local function split(str, sep)
  local result = {}
  for field in string.gmatch(str, (("[^%s]+"):format(sep))) do
    table.insert(result, field)
  end
  return result
end

---@param buf number
---@param filepath string
---@return HistoryItem[]
function M.get_history(buf, filepath)
  local fh_module = get_fh()
  local entries = vim.iter(fh_module.file_history()):flatten():totable()
  local items = {}

  for _, entry in pairs(entries) do
    if entry and entry ~= "" then
      local fields = split(entry, '\x09')
      local item = {
        source = "git",
        id = fields[3],
        time_ago = fields[1],
        date = fields[2],
        hash = fields[3],
        file = fields[4],
        label = fields[5] or '',
        timestamp = M._parse_relative_time(fields[1]),
        is_save_point = true,
        branch_depth = 0,
        text = (fields[5] or '') .. ' ' .. fields[1] .. ' ' .. fields[2],
      }
      table.insert(items, item)
    end
  end

  dbg.debug("git_provider", "Retrieved history", { filepath = filepath, count = #items })
  return items
end

---@param item HistoryItem
---@return string[]
function M.get_content(item)
  local fh_module = get_fh()
  return fh_module.get_file(item.file, item.hash)
end

---@param item HistoryItem
---@return boolean
function M.can_revert(item)
  return item.hash ~= nil and item.file ~= nil
end

---@param item HistoryItem
---@param buf number
---@return boolean
function M.revert(item, buf)
  if not M.can_revert(item) then
    return false
  end

  local lines = M.get_content(item)
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, lines)
  dbg.info("git_provider", "Reverted buffer", { hash = item.hash, file = item.file })
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
    delete_history = true,
    purge_history = true,
  }
  return supported[action] == true
end

---@param item HistoryItem
---@param filepath string
---@return string[]
function M.get_log(item, filepath)
  local fh_module = get_fh()
  return fh_module.get_log(filepath, item.hash)
end

function M._parse_relative_time(time_str)
  if not time_str then
    return os.time()
  end

  local now = os.time()
  local amount, unit = time_str:match("(%d+)%s+(%w+)")

  if not amount then
    return now
  end

  amount = tonumber(amount)
  local seconds_map = {
    second = 1,
    seconds = 1,
    minute = 60,
    minutes = 60,
    hour = 3600,
    hours = 3600,
    day = 86400,
    days = 86400,
    week = 604800,
    weeks = 604800,
    month = 2592000,
    months = 2592000,
    year = 31536000,
    years = 31536000,
  }

  local multiplier = seconds_map[unit] or 1
  return now - (amount * multiplier)
end

return M
