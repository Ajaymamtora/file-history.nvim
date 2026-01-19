--- Provider registry and unified interface for file history sources
--- Supports multiple history sources (git, undo) with a common interface

local dbg = require("file_history.debug")

local M = {}

---@class FileHistoryProvider
---@field name string Provider identifier ("git" or "undo")
---@field get_history fun(buf: number, filepath: string): HistoryItem[]
---@field get_content fun(item: HistoryItem): string[]
---@field can_revert fun(item: HistoryItem): boolean
---@field revert fun(item: HistoryItem, buf: number): boolean
---@field supports_action fun(action: string): boolean

---@class HistoryItem
---@field source "git"|"undo" Which provider this came from
---@field id string Unique identifier (hash or seq number)
---@field timestamp number Unix timestamp
---@field time_ago string Human readable "2 hours ago"
---@field date string Formatted date
---@field label string Display label (tag or "undo #N")
---@field is_save_point boolean Whether this was a file save
---@field branch_depth number 0 for main timeline, >0 for branches
---@field text string Searchable text for picker
---@field file string? Filepath (for git provider)
---@field hash string? Git commit hash (for git provider)
---@field seq number? Undo sequence number (for undo provider)
---@field buf number? Buffer reference (for undo provider)

---@type table<string, FileHistoryProvider>
M.providers = {}

--- Register a provider
---@param name string Provider name
---@param provider FileHistoryProvider Provider implementation
function M.register(name, provider)
  dbg.debug("providers", "Registering provider", { name = name })
  M.providers[name] = provider
  provider.name = name
end

--- Get combined history from multiple sources
---@param sources string[] List of source names to query (e.g., {"git", "undo"})
---@param buf number Buffer number
---@param filepath string File path
---@return HistoryItem[]
function M.get_history(sources, buf, filepath)
  local items = {}

  for _, source in ipairs(sources) do
    local provider = M.providers[source]
    if provider then
      dbg.debug("providers", "Fetching history from provider", { source = source, filepath = filepath })
      local ok, provider_items = pcall(provider.get_history, buf, filepath)
      if ok and provider_items then
        for _, item in ipairs(provider_items) do
          item.source = source
          table.insert(items, item)
        end
        dbg.debug("providers", "Provider returned items", { source = source, count = #provider_items })
      else
        dbg.warn("providers", "Provider failed to get history", { source = source, error = provider_items })
      end
    else
      dbg.warn("providers", "Provider not found", { source = source })
    end
  end

  -- Sort by timestamp descending (newest first)
  table.sort(items, function(a, b)
    return (a.timestamp or 0) > (b.timestamp or 0)
  end)

  dbg.info("providers", "Combined history items", { total = #items, sources = sources })
  return items
end

--- Get content at a specific history point
---@param item HistoryItem History item
---@return string[] Lines of content
function M.get_content(item)
  local provider = M.providers[item.source]
  if not provider then
    dbg.warn("providers", "Provider not found for item", { source = item.source })
    return {}
  end

  local ok, lines = pcall(provider.get_content, item)
  if not ok then
    dbg.warn("providers", "Failed to get content", { source = item.source, error = lines })
    return {}
  end

  return lines or {}
end

--- Revert buffer to a history point
---@param item HistoryItem History item
---@param buf number Buffer to revert
---@return boolean Success
function M.revert(item, buf)
  local provider = M.providers[item.source]
  if not provider then
    dbg.warn("providers", "Provider not found for revert", { source = item.source })
    return false
  end

  if provider.can_revert and not provider.can_revert(item) then
    dbg.warn("providers", "Provider cannot revert this item", { source = item.source, id = item.id })
    return false
  end

  local ok, result = pcall(provider.revert, item, buf)
  if not ok then
    dbg.warn("providers", "Revert failed", { source = item.source, error = result })
    return false
  end

  dbg.info("providers", "Reverted to history point", { source = item.source, id = item.id })
  return result ~= false
end

--- Check if an action is supported for a given item
---@param item HistoryItem History item
---@param action string Action name
---@return boolean
function M.supports_action(item, action)
  local provider = M.providers[item.source]
  if not provider then
    return false
  end

  if provider.supports_action then
    return provider.supports_action(action)
  end

  -- Default: all actions supported
  return true
end

--- Get list of registered provider names
---@return string[]
function M.get_provider_names()
  local names = {}
  for name, _ in pairs(M.providers) do
    table.insert(names, name)
  end
  return names
end

--- Get a specific provider
---@param name string Provider name
---@return FileHistoryProvider?
function M.get_provider(name)
  return M.providers[name]
end

return M
