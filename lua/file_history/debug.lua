-- Debug logging module for file-history.nvim
-- Provides comprehensive logging when opts.debug = true

local M = {}

-- Debug state
M.enabled = false
M.log_file = nil
M.log_to_file = false

-- Log levels
M.LEVEL = {
  TRACE = 1,
  DEBUG = 2,
  INFO = 3,
  WARN = 4,
  ERROR = 5,
}

M.level_names = {
  [1] = "TRACE",
  [2] = "DEBUG",
  [3] = "INFO",
  [4] = "WARN",
  [5] = "ERROR",
}

M.min_level = M.LEVEL.TRACE

-- Session log buffer (keeps last N entries in memory)
M.log_buffer = {}
M.max_buffer_size = 500

---Format a log message with timestamp and level
---@param level number
---@param module string
---@param msg string
---@param data? table
---@return string
local function format_message(level, module, msg, data)
  local timestamp = os.date("%H:%M:%S")
  local level_name = M.level_names[level] or "UNKNOWN"
  local formatted = string.format("[%s][%s][%s] %s", timestamp, level_name, module, msg)
  
  if data then
    local data_str = vim.inspect(data, { depth = 3, newline = " ", indent = "" })
    -- Truncate very long data
    if #data_str > 500 then
      data_str = data_str:sub(1, 500) .. "...(truncated)"
    end
    formatted = formatted .. " | " .. data_str
  end
  
  return formatted
end

---Add entry to log buffer
---@param entry string
local function buffer_log(entry)
  table.insert(M.log_buffer, entry)
  -- Trim buffer if too large
  while #M.log_buffer > M.max_buffer_size do
    table.remove(M.log_buffer, 1)
  end
end

---Write to log file if enabled
---@param entry string
local function file_log(entry)
  if not M.log_to_file or not M.log_file then
    return
  end
  
  local f = io.open(M.log_file, "a")
  if f then
    f:write(entry .. "\n")
    f:close()
  end
end

---Core logging function
---@param level number
---@param module string
---@param msg string
---@param data? table
function M.log(level, module, msg, data)
  if not M.enabled then
    return
  end
  
  if level < M.min_level then
    return
  end
  
  local entry = format_message(level, module, msg, data)
  buffer_log(entry)
  file_log(entry)
  
  -- Also print to messages for immediate visibility
  if level >= M.LEVEL.WARN then
    vim.schedule(function()
      vim.notify("[FileHistory] " .. entry, level >= M.LEVEL.ERROR and vim.log.levels.ERROR or vim.log.levels.WARN)
    end)
  end
end

-- Convenience functions for each module
function M.trace(module, msg, data)
  M.log(M.LEVEL.TRACE, module, msg, data)
end

function M.debug(module, msg, data)
  M.log(M.LEVEL.DEBUG, module, msg, data)
end

function M.info(module, msg, data)
  M.log(M.LEVEL.INFO, module, msg, data)
end

function M.warn(module, msg, data)
  M.log(M.LEVEL.WARN, module, msg, data)
end

function M.error(module, msg, data)
  M.log(M.LEVEL.ERROR, module, msg, data)
end

---Get all buffered logs as a string
---@return string
function M.get_logs()
  return table.concat(M.log_buffer, "\n")
end

---Clear the log buffer
function M.clear_logs()
  M.log_buffer = {}
end

---Show logs in a new buffer
function M.show_logs()
  local logs = M.get_logs()
  if logs == "" then
    vim.notify("[FileHistory] No debug logs available. Enable with debug = true in setup.", vim.log.levels.INFO)
    return
  end
  
  -- Create a new buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "FileHistory Debug Logs")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(logs, "\n"))
  vim.bo[buf].filetype = "log"
  vim.bo[buf].modifiable = false
  vim.bo[buf].buftype = "nofile"
  
  -- Open in a new tab
  vim.cmd("tabnew")
  vim.api.nvim_win_set_buf(0, buf)
  
  -- Jump to end
  vim.cmd("normal! G")
end

---Copy logs to clipboard
function M.copy_logs()
  local logs = M.get_logs()
  if logs == "" then
    vim.notify("[FileHistory] No debug logs available.", vim.log.levels.INFO)
    return
  end
  
  vim.fn.setreg("+", logs)
  vim.notify("[FileHistory] Debug logs copied to clipboard (" .. #M.log_buffer .. " entries)", vim.log.levels.INFO)
end

---Setup debug module
---@param opts? {enabled?: boolean, log_file?: string, min_level?: number}
function M.setup(opts)
  opts = opts or {}
  
  M.enabled = opts.enabled or false
  M.log_file = opts.log_file
  M.log_to_file = opts.log_file ~= nil
  M.min_level = opts.min_level or M.LEVEL.TRACE
  
  if M.enabled then
    M.info("debug", "Debug logging enabled", {
      log_file = M.log_file,
      min_level = M.level_names[M.min_level],
    })
  end
end

return M
