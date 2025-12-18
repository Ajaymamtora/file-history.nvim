local has_snacks_picker, snacks_picker = pcall(require, "snacks.picker")
if not has_snacks_picker then
  error("This plugin requires folke/snacks.nvim")
end

local fh = require("file_history.fh")
local actions = require("file_history.actions")
local preview_module = require("file_history.preview")
local dbg = require("file_history.debug")

-- Set default values for highlighting groups
vim.cmd("highlight default link FileHistoryTime Number")
vim.cmd("highlight default link FileHistoryDate Function")
vim.cmd("highlight default link FileHistoryFile Keyword")
vim.cmd("highlight default link FileHistoryTag Comment")

local M = {}

local defaults = {
  -- This is the location where it will create your file history repository
  backup_dir = "~/.file-history-git",
  -- command line to execute git
  git_cmd = "git",
  -- Enable debug logging
  debug = false,
  -- Diff options passed to vim.diff()
  -- See :help vim.diff() for all available options
  diff_opts = {
    result_type = "unified",
    ctxlen = 3,
    algorithm = "histogram", -- Better for real-world diffs with scattered changes
    linematch = 60, -- Second-stage diff for aligning lines within hunks
  },
  -- Preview options
  preview = {
    header_style = "text", -- "text", "raw", or "none"
    highlight_style = "full", -- "full" or "text" - whether to extend highlights to full line width
    wrap = false, -- whether to wrap lines in preview window
    show_no_newline = true, -- whether to show "\ No newline at end of file" markers
  },
  key_bindings = {
    -- Actions
    open_buffer_diff_tab = "<M-d>",
    open_file_diff_tab = "<M-d>",
    revert_to_selected = "<C-r>",
    toggle_incremental = "<M-l>",
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

local function preview_file_history(ctx, data)
  dbg.trace("init", "preview_file_history called", {
    item_hash = ctx.item and ctx.item.hash,
    item_file = ctx.item and ctx.item.file,
    data_log = data.log,
    ctx_item_log = ctx.item and ctx.item.log,
  })

  if data.log ~= ctx.item.log then
    if data.log == true then
      dbg.debug("init", "Fetching git log for display")
      ctx.item.diff = table.concat(fh.get_log(ctx.item.file, ctx.item.hash), '\n')
      ctx.item.log = true
    else
      if not data.buf_lines then
        dbg.warn("init", "No buffer lines available for diff")
        return
      end
      
      dbg.debug("init", "Generating diff", {
        buf_lines_count = #data.buf_lines,
        file = ctx.item.file,
        hash = ctx.item.hash,
      })
      
      local parent_lines = fh.get_file(ctx.item.file, ctx.item.hash)
      dbg.debug("init", "Retrieved parent file", {
        parent_lines_count = #parent_lines,
        parent_first_line = parent_lines[1],
        parent_last_line = parent_lines[#parent_lines],
      })
      
      local buf_content = table.concat(data.buf_lines, '\n') .. '\n'
      local parent_content = table.concat(parent_lines, '\n') .. '\n'
      
      -- Normalize line endings: strip \r to handle Windows vs Unix line ending mismatch
      -- This is critical when git history has CRLF but buffer has LF
      buf_content = buf_content:gsub('\r', '')
      parent_content = parent_content:gsub('\r', '')
      
      dbg.trace("init", "Content lengths for diff", {
        buf_content_len = #buf_content,
        parent_content_len = #parent_content,
        buf_first_100 = buf_content:sub(1, 100),
        parent_first_100 = parent_content:sub(1, 100),
      })
      
      local diff_opts = M.opts.diff_opts
      dbg.debug("init", "Calling vim.diff with options", diff_opts)
      
      ctx.item.diff = vim.diff(buf_content, parent_content, diff_opts)
      
      dbg.info("init", "Diff generated", {
        diff_length = #(ctx.item.diff or ""),
        diff_lines = ctx.item.diff and #vim.split(ctx.item.diff, "\n") or 0,
        diff_preview = ctx.item.diff and ctx.item.diff:sub(1, 200) or "(empty)",
        is_empty = ctx.item.diff == "" or ctx.item.diff == nil,
      })
      
      ctx.item.log = false
    end
  else
    dbg.trace("init", "Using cached diff", { cached_log = ctx.item.log })
  end

  -- Get filepath for header
  local bufname = vim.api.nvim_buf_get_name(data.buf)
  local filepath = bufname ~= "" and bufname or "[No Name]"

  dbg.debug("init", "Rendering diff preview", { filepath = filepath })
  -- Use custom preview rendering with highlighting
  preview_module.render_diff(ctx, ctx.item.diff, filepath)
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
  -- Use custom preview rendering with highlighting
  preview_module.render_diff(ctx, ctx.item.diff, filepath)
end

local function file_history_finder(_)
  local entries = vim.iter(fh.file_history()):flatten():totable()
  local results = {}
  for _, entry in pairs(entries) do
    if entry and entry ~= "" then
      local fields = split(entry, '\x09')
      local result = {
        time = fields[1],
        date = fields[2],
        hash = fields[3],
        file = fields[4],
        tag = fields[5] or ''
      }
      result.text = result.tag .. ' ' .. result.time .. ' ' .. result.date
      table.insert(results, result)
    end
  end
  return results
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
        [M.opts.key_bindings.revert_to_selected] = { "revert_to_selected", desc = "Revert current buffer to selected commit", mode = { "n", "i" } },
        [M.opts.key_bindings.toggle_incremental] = { "toggle_incremental", desc = "Toggle incremental diff mode", mode = { "n", "i" } },
      }
    }
  }
  fhp.finder = file_history_finder
  fhp.format = function(item)
    local ret = {}
    ret[#ret + 1] = { str_prepare(item.time or "", 16), "FileHistoryTime" }
    ret[#ret + 1] = { " " }
    ret[#ret + 1] = { str_prepare(item.date or "", 32), "FileHistoryDate" }
    ret[#ret + 1] = { " " }
    ret[#ret + 1] = { item.tag or "", "FileHistoryTag" }
    return ret
  end
  fhp.preview = function(ctx) preview_file_history(ctx, data) end
  fhp.actions = {
    open_buffer_diff_tab = function(_, item)
      actions.open_buffer_diff_tab(item, data)
    end,
    revert_to_selected = function(picker, item)
      actions.revert_to_selected(item, data)
      picker:close()
    end,
    toggle_incremental = function(picker, _)
      data.log = not data.log
      picker.preview:refresh(picker)
    end
  }
  fhp.confirm = function(_, item)
    actions.open_selected_hash_in_new_tab(item, data)
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

function M.history()
  local data = prepare_picker_data()
  snacks_picker.pick(file_history_picker(data))
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
              [M.opts.key_bindings.toggle_incremental] = { "toggle_incremental", desc = "Toggle incremental diff mode", mode = { "n", "i" } },
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
        toggle_incremental = function(picker, _)
          data.log = not data.log
          picker.preview:refresh(picker)
        end
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
  elseif args.fargs[1] == "files" then
    M.files()
  elseif args.fargs[1] == "backup" then
    M.backup()
  elseif args.fargs[1] == "query" then
    M.query()
  elseif args.fargs[1] == "debug" then
    -- Show debug logs in a new buffer
    dbg.show_logs()
  elseif args.fargs[1] == "debug_copy" then
    -- Copy debug logs to clipboard
    dbg.copy_logs()
  elseif args.fargs[1] == "debug_clear" then
    -- Clear debug logs
    dbg.clear_logs()
    vim.notify("[FileHistory] Debug logs cleared", vim.log.levels.INFO)
  end
end

function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", defaults, opts or {})
  
  -- Setup debug module first
  dbg.setup({ enabled = M.opts.debug })
  dbg.info("init", "FileHistory setup starting", {
    debug = M.opts.debug,
    backup_dir = M.opts.backup_dir,
    diff_opts = M.opts.diff_opts,
  })
  
  fh.setup(opts)

  -- Setup preview module with options
  preview_module.setup(M.opts.preview or {})
  dbg.debug("init", "Preview module configured", M.opts.preview)

  vim.api.nvim_create_user_command("FileHistory", commands, { 
    nargs = 1,
    complete = function()
      return { "history", "files", "backup", "query", "debug", "debug_copy", "debug_clear" }
    end,
  })
  
  dbg.info("init", "FileHistory setup complete")
end

-- Expose debug functions for programmatic access
M.show_debug_logs = dbg.show_logs
M.copy_debug_logs = dbg.copy_logs
M.get_debug_logs = dbg.get_logs
M.clear_debug_logs = dbg.clear_logs

return M
