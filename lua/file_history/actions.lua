local pfiletype = require "plenary.filetype"
local has_fh, fh = pcall(require, "file_history.fh")
if not has_fh then
  error("Couldn't load file_history module")
end

local fh_actions = {}

local function get_providers()
  return require("file_history.providers")
end

-- Helper to extract additions or deletions from a diff
-- @param diff_text string The unified diff text
-- @param extract_type "add"|"delete" Which lines to extract
-- @return string[] Lines without the diff prefix
local function extract_diff_lines(diff_text, extract_type)
  if not diff_text or diff_text == "" then
    return {}
  end

  local lines = vim.split(diff_text, "\n", { plain = true })
  local result = {}
  local pattern = extract_type == "add" and "^%+" or "^%-"
  local header_pattern = extract_type == "add" and "^%+%+%+" or "^%-%-%-"

  for _, line in ipairs(lines) do
    -- Match the line type but exclude header lines (--- or +++)
    if line:match(pattern) and not line:match(header_pattern) then
      -- Strip the leading +/- character
      table.insert(result, line:sub(2))
    end
  end

  return result
end

-- Helper to generate diff for file_history picker (current buffer vs snapshot)
local function generate_file_history_diff(item, data)
  if not data.buf_lines then
    return nil
  end

  local parent_lines
  if item.source == "undo" then
    local providers = get_providers()
    parent_lines = providers.get_content(item)
  else
    parent_lines = fh.get_file(item.file, item.hash)
  end

  local buf_content = table.concat(data.buf_lines, '\n') .. '\n'
  local parent_content = table.concat(parent_lines, '\n') .. '\n'

  buf_content = buf_content:gsub('\r', '')
  parent_content = parent_content:gsub('\r', '')

  return vim.diff(buf_content, parent_content, {
    result_type = "unified",
    ctxlen = 0,
  })
end

-- Helper to generate diff for query picker (HEAD vs snapshot)
local function generate_query_diff(item)
  local head_lines = fh.get_file(item.file, "HEAD")
  local parent_lines = fh.get_file(item.file, item.hash)

  local head_content = table.concat(head_lines, '\n') .. '\n'
  local parent_content = table.concat(parent_lines, '\n') .. '\n'

  -- Normalize line endings
  head_content = head_content:gsub('\r', '')
  parent_content = parent_content:gsub('\r', '')

  return vim.diff(head_content, parent_content, {
    result_type = "unified",
    ctxlen = 0,
  })
end

fh_actions.yank_additions = function(item, data)
  local diff_text
  if data and data.buf_lines then
    -- file_history picker context
    diff_text = generate_file_history_diff(item, data)
  else
    -- query picker context
    diff_text = generate_query_diff(item)
  end

  local additions = extract_diff_lines(diff_text, "add")
  if #additions == 0 then
    vim.notify("[FileHistory] No additions to yank", vim.log.levels.INFO)
    return
  end

  local text = table.concat(additions, "\n")
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)
  vim.notify(string.format("[FileHistory] Yanked %d addition(s)", #additions), vim.log.levels.INFO)
end

fh_actions.yank_deletions = function(item, data)
  local diff_text
  if data and data.buf_lines then
    -- file_history picker context
    diff_text = generate_file_history_diff(item, data)
  else
    -- query picker context
    diff_text = generate_query_diff(item)
  end

  local deletions = extract_diff_lines(diff_text, "delete")
  if #deletions == 0 then
    vim.notify("[FileHistory] No deletions to yank", vim.log.levels.INFO)
    return
  end

  local text = table.concat(deletions, "\n")
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)
  vim.notify(string.format("[FileHistory] Yanked %d deletion(s)", #deletions), vim.log.levels.INFO)
end

fh_actions.revert_to_selected = function(item, data)
  if not data.buf then
    return
  end
  local parent_lines = fh.get_file(item.file, item.hash)
  -- Revert current buffer to selected version
  vim.api.nvim_buf_set_lines(data.buf, 0, -1, true, parent_lines)
end

fh_actions.delete_history = function(picker)
  local items = picker:selected({ fallback = true })
  for _, item in pairs(items) do
    fh.delete_file(item.name)
  end
end

fh_actions.purge_history = function(picker)
  local items = picker:selected({ fallback = true })
  for _, item in pairs(items) do
    fh.purge_file(item.name)
  end
end

fh_actions.open_file_hash_in_new_tab = function(item, filetype)
  local parent_lines = fh.get_file(item.file, item.hash)
  -- Open new tab
  vim.cmd('tabnew')
  -- Diff buffer with selected version
  local nwin = vim.api.nvim_get_current_win()
  local nbufnr = vim.api.nvim_create_buf(true, true)
  local bufname = item.hash .. ':' .. item.file
  vim.api.nvim_buf_set_name(nbufnr, bufname)
  vim.api.nvim_buf_set_option(nbufnr, 'filetype', filetype)
  vim.api.nvim_buf_set_lines(nbufnr, 0, -1, true, parent_lines)
  vim.api.nvim_buf_set_option(nbufnr, 'modifiable', false)
  vim.api.nvim_win_set_buf(nwin, nbufnr)
end

-- Open item's hash in new tab. Item is a version of the current buffer file
fh_actions.open_selected_hash_in_new_tab = function(item, data)
  if not data.buf then
    return
  end
  local filetype = vim.api.nvim_buf_get_option(data.buf, 'filetype')
  fh_actions.open_file_hash_in_new_tab(item, filetype)
end

-- Open item's hash in new tab.
fh_actions.open_selected_file_hash_in_new_tab = function(item)
  local filetype = pfiletype.detect(item.file, {})
  fh_actions.open_file_hash_in_new_tab(item, filetype)
end

local function create_buffer_for_file(file, hash)
  local lines = fh.get_file(file, hash)
  local filetype = pfiletype.detect(file, {})
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_option(buf, 'filetype', filetype)
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  return buf
end

-- Open a diff between the buffer and another version of it
fh_actions.open_buffer_diff_tab = function(item, data)
  if not data.buf then
    return
  end
  local pbuf = create_buffer_for_file(item.file, item.hash)
  -- Open new tab
  vim.cmd('tabnew')
  -- Diff buffer with selected version
  local nwin = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(nwin, pbuf)
  vim.cmd('vsplit')
  vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), data.buf)
  -- Diffthis!
  vim.cmd('windo diffthis')
end

fh_actions.open_undo_diff_tab = function(item, data, content)
  if not data.buf then
    return
  end
  local filetype = vim.api.nvim_buf_get_option(data.buf, 'filetype')
  local pbuf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_option(pbuf, 'filetype', filetype)
  vim.api.nvim_buf_set_lines(pbuf, 0, -1, true, content)
  vim.api.nvim_buf_set_option(pbuf, 'modifiable', false)
  vim.api.nvim_buf_set_name(pbuf, "undo#" .. item.seq .. ":" .. (item.file or "[buffer]"))

  vim.cmd('tabnew')
  local nwin = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(nwin, pbuf)
  vim.cmd('vsplit')
  vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), data.buf)
  vim.cmd('windo diffthis')
end

fh_actions.open_undo_snapshot_tab = function(item, data, content)
  local filetype = "text"
  if data and data.buf then
    filetype = vim.api.nvim_buf_get_option(data.buf, 'filetype')
  elseif item.file then
    filetype = pfiletype.detect(item.file, {})
  end

  vim.cmd('tabnew')
  local nwin = vim.api.nvim_get_current_win()
  local nbufnr = vim.api.nvim_create_buf(true, true)
  local bufname = "undo#" .. item.seq .. ":" .. (item.file or "[buffer]")
  vim.api.nvim_buf_set_name(nbufnr, bufname)
  vim.api.nvim_buf_set_option(nbufnr, 'filetype', filetype)
  vim.api.nvim_buf_set_lines(nbufnr, 0, -1, true, content)
  vim.api.nvim_buf_set_option(nbufnr, 'modifiable', false)
  vim.api.nvim_win_set_buf(nwin, nbufnr)
end

-- Open a diff between two versions of a file
fh_actions.open_file_diff_tab = function(item)
  local buf = create_buffer_for_file(item.file, "HEAD")
  local pbuf = create_buffer_for_file(item.file, item.hash)
  -- Open new tab
  vim.cmd('tabnew')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, pbuf)
  vim.cmd('vsplit')
  vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), buf)
  -- Diffthis!
  vim.cmd('windo diffthis')
end

return fh_actions

