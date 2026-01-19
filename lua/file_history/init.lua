local has_snacks_picker, snacks_picker = pcall(require, "snacks.picker")
if not has_snacks_picker then
  error("This plugin requires folke/snacks.nvim")
end

local fh = require("file_history.fh")
local actions = require("file_history.actions")
local preview_module = require("file_history.preview")
local dbg = require("file_history.debug")
local providers = require("file_history.providers")

vim.cmd("highlight default link FileHistoryTime Number")
vim.cmd("highlight default link FileHistoryDate Function")
vim.cmd("highlight default link FileHistoryFile Keyword")
vim.cmd("highlight default link FileHistoryTag Comment")
vim.cmd("highlight default link FileHistorySourceGit GitSignsAdd")
vim.cmd("highlight default link FileHistorySourceUndo DiagnosticInfo")

local M = {}

local defaults = {
  backup_dir = "~/.file-history-git",
  git_cmd = "git",
  debug = false,
  sources = {
    git = true,
    undo = true,
  },
  display = {
    show_source = true,
    source_icons = {
      git = "",
      undo = "",
    },
    source_labels = {
      git = "Git History",
      undo = "Vim Undo",
    },
  },
  undo = {
    include_branches = true,
    save_points_only = false,
    max_entries = 100,
  },
  diff_opts = {
    result_type = "unified",
    ctxlen = 3,
    algorithm = "histogram",
    linematch = 60,
  },
  preview = {
    header_style = "text",
    highlight_style = "full",
    wrap = false,
    show_no_newline = true,
  },
  key_bindings = {
    open_buffer_diff_tab = "<M-d>",
    open_file_diff_tab = "<M-d>",
    open_snapshot_tab = "<M-o>",
    revert_to_selected = "<C-r>",
    toggle_incremental = "<M-l>",
    yank_additions = "<M-a>",
    yank_deletions = "<M-x>",
    delete_history = "<M-d>",
    purge_history = "<M-p>",
  },
}


local function str_prepare(str, len)
  local s
  if #str > len then
    s = string.sub(str, 1, len)
  else
    s = str
  end
  local format = "%-" .. tostring(len) .. "s"
  return string.format(format, s)
end

local function split(str, sep)
  local result = {}
  for field in string.gmatch(str, ("[^%s]+"):format(sep)) do
    table.insert(result, field)
  end
  return result
end

---Parse unified diff hunk header to extract line range information
---@param header string Hunk header line like "@@ -10,5 +12,7 @@ function foo()"
---@return {old_start: number, old_count: number, new_start: number, new_count: number}?
local function parse_hunk_header(header)
  local old_start, old_count, new_start, new_count = header:match("@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
  if not old_start then
    return nil
  end
  return {
    old_start = tonumber(old_start) or 0,
    old_count = old_count ~= "" and tonumber(old_count) or 1,
    new_start = tonumber(new_start) or 0,
    new_count = new_count ~= "" and tonumber(new_count) or 1,
  }
end

---Check if a hunk overlaps with a given line range
---@param hunk_start number Start line of the hunk
---@param hunk_count number Number of lines in the hunk
---@param range_start number Start line of the range
---@param range_end number End line of the range
---@return boolean
local function hunk_overlaps_range(hunk_start, hunk_count, range_start, range_end)
  local hunk_end = hunk_start + math.max(0, hunk_count - 1)
  return not (hunk_end < range_start or hunk_start > range_end)
end

---Check if any hunk in a diff affects the given line range
---@param diff_text string The unified diff text
---@param range_start number Start line of the range (1-indexed)
---@param range_end number End line of the range (1-indexed)
---@return boolean
local function diff_affects_range(diff_text, range_start, range_end)
  if not diff_text or diff_text == "" then
    return false
  end
  for line in diff_text:gmatch("[^\n]+") do
    if line:match("^@@") then
      local hunk = parse_hunk_header(line)
      if hunk and hunk_overlaps_range(hunk.new_start, hunk.new_count, range_start, range_end) then
        return true
      end
    end
  end
  return false
end

---Filter a unified diff to only include hunks affecting a line range
---@param diff_text string The unified diff text
---@param range_start number Start line of the range (1-indexed)
---@param range_end number End line of the range (1-indexed)
---@return string Filtered diff text
local function filter_diff_to_range(diff_text, range_start, range_end)
  if not diff_text or diff_text == "" then
    return ""
  end

  local result = {}
  local current_hunk = {}
  local include_current_hunk = false

  for line in diff_text:gmatch("[^\n]+") do
    if line:match("^@@") then
      if include_current_hunk and #current_hunk > 0 then
        for _, hunk_line in ipairs(current_hunk) do
          table.insert(result, hunk_line)
        end
      end
      current_hunk = { line }
      local hunk = parse_hunk_header(line)
      include_current_hunk = hunk and hunk_overlaps_range(hunk.new_start, hunk.new_count, range_start, range_end)
    elseif #current_hunk > 0 then
      table.insert(current_hunk, line)
    end
  end

  if include_current_hunk and #current_hunk > 0 then
    for _, hunk_line in ipairs(current_hunk) do
      table.insert(result, hunk_line)
    end
  end

  return table.concat(result, "\n")
end

local function preview_file_history(ctx, data)
  dbg.trace("init", "preview_file_history called", {
    item_source = ctx.item and ctx.item.source,
    item_hash = ctx.item and ctx.item.hash,
    item_seq = ctx.item and ctx.item.seq,
    item_file = ctx.item and ctx.item.file,
    data_log = data.log,
    ctx_item_log = ctx.item and ctx.item.log,
  })

  if data.log ~= ctx.item.log then
    if data.log == true then
      if ctx.item.source == "git" then
        dbg.debug("init", "Fetching git log for display")
        ctx.item.diff = table.concat(fh.get_log(ctx.item.file, ctx.item.hash), '\n')
      else
        ctx.item.diff = "Log view not available for undo history"
      end
      ctx.item.log = true
    else
      if not data.buf_lines then
        dbg.warn("init", "No buffer lines available for diff")
        return
      end

      dbg.debug("init", "Generating diff", {
        source = ctx.item.source,
        buf_lines_count = #data.buf_lines,
        file = ctx.item.file,
      })

      local parent_lines = providers.get_content(ctx.item)
      dbg.debug("init", "Retrieved parent content", {
        parent_lines_count = #parent_lines,
        parent_first_line = parent_lines[1],
        parent_last_line = parent_lines[#parent_lines],
      })

      local buf_content = table.concat(data.buf_lines, '\n') .. '\n'
      local parent_content = table.concat(parent_lines, '\n') .. '\n'

      buf_content = buf_content:gsub('\r', '')
      parent_content = parent_content:gsub('\r', '')

      dbg.trace("init", "Content lengths for diff", {
        buf_content_len = #buf_content,
        parent_content_len = #parent_content,
      })

      local diff_opts = M.opts.diff_opts
      dbg.debug("init", "Calling vim.diff with options", diff_opts)

      ctx.item.diff = vim.diff(buf_content, parent_content, diff_opts)

      dbg.info("init", "Diff generated", {
        diff_length = #(ctx.item.diff or ""),
        diff_lines = ctx.item.diff and #vim.split(ctx.item.diff, "\n") or 0,
        is_empty = ctx.item.diff == "" or ctx.item.diff == nil,
      })

      ctx.item.log = false
    end
  else
    dbg.trace("init", "Using cached diff", { cached_log = ctx.item.log })
  end

  local bufname = vim.api.nvim_buf_get_name(data.buf)
  local filepath = bufname ~= "" and bufname or "[No Name]"

  dbg.debug("init", "Rendering diff preview", { filepath = filepath })
  preview_module.render_diff(ctx, ctx.item.diff, filepath, ctx.item.source)
end

local function preview_file_history_range(ctx, data)
  local range_start = data.range.start_line
  local range_end = data.range.end_line

  if data.log ~= ctx.item.log then
    if data.log == true then
      if ctx.item.source == "git" then
        ctx.item.diff = table.concat(fh.get_log(ctx.item.file, ctx.item.hash), '\n')
      else
        ctx.item.diff = "Log view not available for undo history"
      end
      ctx.item.log = true
    else
      local diff = ctx.item.cached_diff
      if not diff then
        if not data.buf_lines then
          return
        end
        local parent_lines = providers.get_content(ctx.item)
        local buf_content = table.concat(data.buf_lines, '\n') .. '\n'
        local parent_content = table.concat(parent_lines, '\n') .. '\n'
        buf_content = buf_content:gsub('\r', '')
        parent_content = parent_content:gsub('\r', '')
        diff = vim.diff(buf_content, parent_content, M.opts.diff_opts)
      end
      ctx.item.diff = filter_diff_to_range(diff, range_start, range_end)
      ctx.item.log = false
    end
  end

  local bufname = vim.api.nvim_buf_get_name(data.buf)
  local filepath = bufname ~= "" and bufname or "[No Name]"
  local range_indicator = string.format(" [L%d-%d]", range_start, range_end)

  preview_module.render_diff(ctx, ctx.item.diff, filepath .. range_indicator, ctx.item.source)
end

local function preview_file_query(ctx, data)
  dbg.trace("init", "preview_file_query called", {
    item_hash = ctx.item and ctx.item.hash,
    item_file = ctx.item and ctx.item.file,
    data_log = data.log,
  })

  if data.log ~= ctx.item.log then
    if data.log == true then
      dbg.debug("init", "Fetching git log for query preview")
      ctx.item.diff = table.concat(fh.get_log(ctx.item.file, ctx.item.hash), '\n')
      ctx.item.log = true
    else
      dbg.debug("init", "Generating diff for query", {
        file = ctx.item.file,
        hash = ctx.item.hash,
      })

      local lines = fh.get_file(ctx.item.file, "HEAD")
      local parent_lines = fh.get_file(ctx.item.file, ctx.item.hash)

      dbg.debug("init", "Retrieved files for query diff", {
        head_lines_count = #lines,
        parent_lines_count = #parent_lines,
      })

      local head_content = table.concat(lines, '\n') .. '\n'
      local parent_content = table.concat(parent_lines, '\n') .. '\n'

      -- Normalize line endings: strip \r to handle Windows vs Unix line ending mismatch
      head_content = head_content:gsub('\r', '')
      parent_content = parent_content:gsub('\r', '')

      local diff_opts = M.opts.diff_opts
      dbg.debug("init", "Calling vim.diff for query with options", diff_opts)

      ctx.item.diff = vim.diff(head_content, parent_content, diff_opts)

      dbg.info("init", "Query diff generated", {
        diff_length = #(ctx.item.diff or ""),
        diff_lines = ctx.item.diff and #vim.split(ctx.item.diff, "\n") or 0,
        is_empty = ctx.item.diff == "" or ctx.item.diff == nil,
      })

      ctx.item.log = false
    end
  end

  -- Get filepath for header
  local filepath = ctx.item.file

  dbg.debug("init", "Rendering query diff preview", { filepath = filepath })
  preview_module.render_diff(ctx, ctx.item.diff, filepath, ctx.item.source)
end

local function file_history_finder(data)
  local sources = {}
  if M.opts.sources.git then
    table.insert(sources, "git")
  end
  if M.opts.sources.undo then
    table.insert(sources, "undo")
  end

  local buf = data.buf
  local filepath = vim.api.nvim_buf_get_name(buf)

  local items = providers.get_history(sources, buf, filepath)

  for _, item in ipairs(items) do
    item.time = item.time_ago
  end

  return items
end

local function file_history_range_finder(data)
  local sources = {}
  if M.opts.sources.git then
    table.insert(sources, "git")
  end
  if M.opts.sources.undo then
    table.insert(sources, "undo")
  end

  local buf = data.buf
  local filepath = vim.api.nvim_buf_get_name(buf)
  local range_start = data.range.start_line
  local range_end = data.range.end_line

  local all_items = providers.get_history(sources, buf, filepath)
  local filtered_items = {}

  local buf_content = table.concat(data.buf_lines, '\n') .. '\n'
  buf_content = buf_content:gsub('\r', '')

  for _, item in ipairs(all_items) do
    local parent_lines = providers.get_content(item)
    local parent_content = table.concat(parent_lines, '\n') .. '\n'
    parent_content = parent_content:gsub('\r', '')

    local diff = vim.diff(buf_content, parent_content, M.opts.diff_opts)

    if diff_affects_range(diff, range_start, range_end) then
      item.time = item.time_ago
      item.cached_diff = diff
      table.insert(filtered_items, item)
    end
  end

  return filtered_items
end

local function file_history_files_finder(_)
  local entries = vim.iter(fh.file_history_files()):flatten():totable()
  if #entries == 0 then
    return {}
  end
  local hostname = vim.fn.hostname()
  local results = {}
  for _, entry in pairs(entries) do
    if entry and entry ~= "" then
      local result = {}
      local index = string.find(entry, '/')
      if index then
        -- If file is local, enable preview
        if hostname == string.sub(entry, 1, index - 1) then
          result.file = string.sub(entry, index)
          result.text = result.file
        else
          result.file = nil
          result.text = entry
        end
        -- This is the name, or reference for deleting/purging etc
        result.name = entry
        result.hash = "HEAD"
        table.insert(results, result)
      end
    end
  end
  return results
end

local function file_history_query_finder(after, before)
  local entries = vim.iter(fh.file_history_query(after, before)):flatten():totable()
  local results = {}
  for _, entry in pairs(entries) do
    if entry and entry ~= "" then
      local fields = split(entry, '\x09')
      local result = {
        date = fields[1],
        hash = fields[2],
        file = fields[3],
        tag = fields[4] or ''
      }
      result.text = result.date .. ' ' .. result.tag .. ' ' .. result.file
      table.insert(results, result)
    end
  end
  return results
end

local function file_history_picker(data)
  local fhp = {}
  fhp.win = {
    title = "FileHistory history",
    input = {
      keys = {
        [M.opts.key_bindings.open_buffer_diff_tab] = { "open_buffer_diff_tab", desc = "Open diff in new tab", mode = { "n", "i" } },
        [M.opts.key_bindings.open_snapshot_tab] = { "open_snapshot_tab", desc = "Open snapshot in new tab", mode = { "n", "i" } },
        [M.opts.key_bindings.toggle_incremental] = { "toggle_incremental", desc = "Toggle incremental diff mode", mode = { "n", "i" } },
        [M.opts.key_bindings.yank_additions] = { "yank_additions", desc = "Yank all additions from diff", mode = { "n", "i" } },
        [M.opts.key_bindings.yank_deletions] = { "yank_deletions", desc = "Yank all deletions from diff", mode = { "n", "i" } },
      }
    }
  }
  fhp.finder = function() return file_history_finder(data) end
  fhp.format = function(item)
    local ret = {}

    if M.opts.display.show_source then
      local icon = M.opts.display.source_icons[item.source] or "?"
      local hl = item.source == "git" and "FileHistorySourceGit" or "FileHistorySourceUndo"
      ret[#ret + 1] = { icon .. " ", hl }
    end

    if item.source == "undo" and item.branch_depth and item.branch_depth > 0 then
      ret[#ret + 1] = { string.rep("│ ", item.branch_depth), "Comment" }
    end

    ret[#ret + 1] = { str_prepare(item.time or "", 16), "FileHistoryTime" }
    ret[#ret + 1] = { " " }
    ret[#ret + 1] = { str_prepare(item.date or "", 32), "FileHistoryDate" }
    ret[#ret + 1] = { " " }
    ret[#ret + 1] = { item.label or item.tag or "", "FileHistoryTag" }
    return ret
  end
  fhp.preview = function(ctx) preview_file_history(ctx, data) end
  fhp.actions = {
    open_buffer_diff_tab = function(_, item)
      if item.source == "git" then
        actions.open_buffer_diff_tab(item, data)
      else
        local content = providers.get_content(item)
        actions.open_undo_diff_tab(item, data, content)
      end
    end,
    open_snapshot_tab = function(_, item)
      if item.source == "git" then
        actions.open_selected_hash_in_new_tab(item, data)
      else
        local content = providers.get_content(item)
        actions.open_undo_snapshot_tab(item, data, content)
      end
    end,
    toggle_incremental = function(picker, _)
      data.log = not data.log
      picker.preview:refresh(picker)
    end,
    yank_additions = function(_, item)
      actions.yank_additions(item, data)
    end,
    yank_deletions = function(_, item)
      actions.yank_deletions(item, data)
    end,
  }
  fhp.confirm = function(picker, item)
    if item.source == "undo" then
      providers.revert(item, data.buf)
    else
      actions.revert_to_selected(item, data)
    end
    picker:close()
  end
  return fhp
end

local function file_history_range_picker(data)
  local fhp = {}
  local range_start = data.range.start_line
  local range_end = data.range.end_line

  fhp.win = {
    title = string.format("FileHistory [L%d-%d]", range_start, range_end),
    input = {
      keys = {
        [M.opts.key_bindings.open_buffer_diff_tab] = { "open_buffer_diff_tab", desc = "Open diff in new tab", mode = { "n", "i" } },
        [M.opts.key_bindings.open_snapshot_tab] = { "open_snapshot_tab", desc = "Open snapshot in new tab", mode = { "n", "i" } },
        [M.opts.key_bindings.toggle_incremental] = { "toggle_incremental", desc = "Toggle incremental diff mode", mode = { "n", "i" } },
        [M.opts.key_bindings.yank_additions] = { "yank_additions", desc = "Yank all additions from diff", mode = { "n", "i" } },
        [M.opts.key_bindings.yank_deletions] = { "yank_deletions", desc = "Yank all deletions from diff", mode = { "n", "i" } },
      }
    }
  }
  fhp.finder = function() return file_history_range_finder(data) end
  fhp.format = function(item)
    local ret = {}

    if M.opts.display.show_source then
      local icon = M.opts.display.source_icons[item.source] or "?"
      local hl = item.source == "git" and "FileHistorySourceGit" or "FileHistorySourceUndo"
      ret[#ret + 1] = { icon .. " ", hl }
    end

    if item.source == "undo" and item.branch_depth and item.branch_depth > 0 then
      ret[#ret + 1] = { string.rep("│ ", item.branch_depth), "Comment" }
    end

    ret[#ret + 1] = { str_prepare(item.time or "", 16), "FileHistoryTime" }
    ret[#ret + 1] = { " " }
    ret[#ret + 1] = { str_prepare(item.date or "", 32), "FileHistoryDate" }
    ret[#ret + 1] = { " " }
    ret[#ret + 1] = { item.label or item.tag or "", "FileHistoryTag" }
    return ret
  end
  fhp.preview = function(ctx) preview_file_history_range(ctx, data) end
  fhp.actions = {
    open_buffer_diff_tab = function(_, item)
      if item.source == "git" then
        actions.open_buffer_diff_tab(item, data)
      else
        local content = providers.get_content(item)
        actions.open_undo_diff_tab(item, data, content)
      end
    end,
    open_snapshot_tab = function(_, item)
      if item.source == "git" then
        actions.open_selected_hash_in_new_tab(item, data)
      else
        local content = providers.get_content(item)
        actions.open_undo_snapshot_tab(item, data, content)
      end
    end,
    toggle_incremental = function(picker, _)
      data.log = not data.log
      picker.preview:refresh(picker)
    end,
    yank_additions = function(_, item)
      actions.yank_additions(item, data)
    end,
    yank_deletions = function(_, item)
      actions.yank_deletions(item, data)
    end,
  }
  fhp.confirm = function(picker, item)
    if item.source == "undo" then
      providers.revert(item, data.buf)
    else
      actions.revert_to_selected(item, data)
    end
    picker:close()
  end
  return fhp
end

local function file_history_files_picker()
  local fhp = {}
  fhp.win = {
    title = "FileHistory files",
    input = {
      keys = {
        [M.opts.key_bindings.delete_history] = { "delete_history", desc = "Delete file's history", mode = { "n", "i" } },
        [M.opts.key_bindings.purge_history] = { "purge_history", desc = "Purge file's history", mode = { "n", "i" } },
      }
    }
  }
  fhp.finder = file_history_files_finder
  fhp.format = function(item)
    local ret = {}
    -- Get filename and directory path
    local filename = vim.fn.fnamemodify(item.text, ":t")
    local dirpath = vim.fn.fnamemodify(item.text, ":h")

    -- Get icon for the file
    local icon, icon_hl = Snacks.util.icon(filename, "file")

    -- Add icon
    ret[#ret + 1] = { icon .. " ", icon_hl or "Normal" }

    -- Add filename (highlighted)
    ret[#ret + 1] = { filename, "Normal" }

    -- Add directory path (dimmed)
    if dirpath and dirpath ~= "." then
      ret[#ret + 1] = { " " }
      ret[#ret + 1] = { dirpath, "Comment" }
    end

    return ret
  end
  fhp.preview = function(ctx)
    if ctx.item.file and vim.uv.fs_stat(ctx.item.file) then
      snacks_picker.preview.file(ctx)
    else
      ctx.preview:reset()
    end
  end
  fhp.actions = {
    delete_history = function(picker, _)
      actions.delete_history(picker)
      picker:close()
    end,
    purge_history = function(picker, _)
      actions.purge_history(picker)
      picker:close()
    end
  }
  fhp.confirm = function(_, item)
    actions.open_selected_file_hash_in_new_tab(item)
  end
  return fhp
end

local function prepare_picker_data()
  local data = {
    buf = nil,
    buf_lines = nil,
    log = false,
  }
  -- Stores the current editor buffer and its lines to diff in previews
  data.buf = vim.api.nvim_get_current_buf()
  data.buf_lines = vim.api.nvim_buf_get_lines(data.buf, 0, -1, true)
  return data
end

local function prepare_picker_data_range(start_line, end_line)
  local data = {
    buf = nil,
    buf_lines = nil,
    log = false,
    range = {
      start_line = start_line,
      end_line = end_line,
    },
  }
  data.buf = vim.api.nvim_get_current_buf()
  data.buf_lines = vim.api.nvim_buf_get_lines(data.buf, 0, -1, true)
  return data
end

function M.history()
  local data = prepare_picker_data()
  snacks_picker.pick(file_history_picker(data))
end

function M.history_range(opts)
  opts = opts or {}

  local start_line = opts.start_line or vim.fn.line("'<")
  local end_line = opts.end_line or vim.fn.line("'>")

  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  if start_line <= 0 or end_line <= 0 then
    vim.notify("[FileHistory] No visual selection", vim.log.levels.WARN)
    return
  end

  local data = prepare_picker_data_range(start_line, end_line)
  snacks_picker.pick(file_history_range_picker(data))
end

function M.files()
  snacks_picker.pick(file_history_files_picker())
end

function M.backup()
  vim.ui.input({ prompt = "Tag name: " }, function(tag)
    if tag then
      fh.set_tag(tag)
    end
    vim.cmd({ cmd = "write" })
  end)
end

function M.query()
  local data = { log = false }
  vim.ui.input({ prompt = "After: " }, function(after)
    vim.ui.input({ prompt = "Before: " }, function(before)
      local fhp = {}
      fhp.win = {
        title = "FileHistory query",
        input = {
          keys = {
            [M.opts.key_bindings.open_file_diff_tab] = { "open_file_diff_tab", desc = "Open diff in new tab", mode = { "n", "i" } },
            [M.opts.key_bindings.open_snapshot_tab] = { "open_snapshot_tab", desc = "Open snapshot in new tab", mode = { "n", "i" } },
            [M.opts.key_bindings.toggle_incremental] = { "toggle_incremental", desc = "Toggle incremental diff mode", mode = { "n", "i" } },
            [M.opts.key_bindings.yank_additions] = { "yank_additions", desc = "Yank all additions from diff", mode = { "n", "i" } },
            [M.opts.key_bindings.yank_deletions] = { "yank_deletions", desc = "Yank all deletions from diff", mode = { "n", "i" } },
          }
        }
      }
      fhp.items = file_history_query_finder(after, before)
      fhp.format = function(item)
        local ret = {}
        ret[#ret + 1] = { str_prepare(item.date or "", 32), "FileHistoryDate" }
        ret[#ret + 1] = { " " }
        ret[#ret + 1] = { str_prepare(item.tag or "", 24), "FileHistoryTag" }
        ret[#ret + 1] = { " " }
        ret[#ret + 1] = { item.file or "", "FileHistoryFile" }
        return ret
      end
      fhp.preview = function(ctx)
        if ctx.item.file and vim.uv.fs_stat(ctx.item.file) then
          preview_file_query(ctx, data)
        else
          ctx.preview:reset()
        end
      end
      fhp.actions = {
        open_file_diff_tab = function(_, item)
          actions.open_file_diff_tab(item)
        end,
        open_snapshot_tab = function(_, item)
          actions.open_selected_file_hash_in_new_tab(item)
        end,
        toggle_incremental = function(picker, _)
          data.log = not data.log
          picker.preview:refresh(picker)
        end,
        yank_additions = function(_, item)
          actions.yank_additions(item, nil)
        end,
        yank_deletions = function(_, item)
          actions.yank_deletions(item, nil)
        end,
      }
      fhp.confirm = function(_, item)
        actions.open_selected_file_hash_in_new_tab(item)
      end
      -- Call the picker
      snacks_picker.pick(fhp)
    end)
  end)
end

local function commands(args)
  if args.fargs[1] == "history" then
    M.history()
  elseif args.fargs[1] == "history_range" then
    M.history_range()
  elseif args.fargs[1] == "files" then
    M.files()
  elseif args.fargs[1] == "backup" then
    M.backup()
  elseif args.fargs[1] == "query" then
    M.query()
  elseif args.fargs[1] == "debug" then
    dbg.show_logs()
  elseif args.fargs[1] == "debug_copy" then
    dbg.copy_logs()
  elseif args.fargs[1] == "debug_clear" then
    dbg.clear_logs()
    vim.notify("[FileHistory] Debug logs cleared", vim.log.levels.INFO)
  end
end

function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", defaults, opts or {})

  dbg.setup({ enabled = M.opts.debug })
  dbg.info("init", "FileHistory setup starting", {
    debug = M.opts.debug,
    backup_dir = M.opts.backup_dir,
    sources = M.opts.sources,
    diff_opts = M.opts.diff_opts,
  })

  fh.setup(opts)

  local git_provider = require("file_history.providers.git")
  local undo_provider = require("file_history.providers.undo")

  providers.register("git", git_provider)
  providers.register("undo", undo_provider)

  undo_provider.setup(M.opts.undo or {})

  local preview_opts = vim.tbl_deep_extend("force", M.opts.preview or {}, {
    source_icons = M.opts.display.source_icons,
    source_labels = M.opts.display.source_labels,
  })
  preview_module.setup(preview_opts)
  dbg.debug("init", "Preview module configured", preview_opts)

  vim.api.nvim_create_user_command("FileHistory", commands, {
    nargs = 1,
    range = true,
    complete = function(ArgLead, CmdLine, CursorPos)
      return { "history", "history_range", "files", "backup", "query", "debug", "debug_copy", "debug_clear" }
    end,
  })

  dbg.info("init", "FileHistory setup complete", {
    registered_providers = providers.get_provider_names(),
  })
end

-- Expose debug functions for programmatic access
M.show_debug_logs = dbg.show_logs
M.copy_debug_logs = dbg.copy_logs
M.get_debug_logs = dbg.get_logs
M.clear_debug_logs = dbg.clear_logs

-- Expose range utilities for testing
M.parse_hunk_header = parse_hunk_header
M.diff_affects_range = diff_affects_range
M.filter_diff_to_range = filter_diff_to_range
M.prepare_picker_data_range = prepare_picker_data_range

return M
