local M = {}

local function deep_copy(value)
  if type(value) ~= "table" then
    return value
  end
  local out = {}
  for k, v in pairs(value) do
    out[k] = deep_copy(v)
  end
  return out
end

local function deep_extend(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" and type(dst[k]) == "table" then
      deep_extend(dst[k], v)
    else
      dst[k] = deep_copy(v)
    end
  end
  return dst
end

local function split_path(path)
  local dir, base = path:match("^(.*)/([^/]+)$")
  if not dir then
    return ".", path
  end
  if dir == "" then
    dir = "/"
  end
  return dir, base
end

local function iter_flatten(tbl)
  local out = {}
  local function walk(v)
    if type(v) == "table" then
      for _, item in ipairs(v) do
        walk(item)
      end
    elseif v ~= nil and v ~= "" then
      table.insert(out, v)
    end
  end
  walk(tbl)
  return out
end

function M.new(opts)
  opts = opts or {}

  local state = {
    next_buf = 1,
    next_win = 1,
    next_ns = 1,
    next_job = 1,

    current_win = 1,
    current_buf = 1,

    bufs = {},
    wins = {},

    cmd_history = {},
    user_commands = {},
    augroups = {},
    autocmds = {},

    highlights = {},
    namespaces = {},

    files = {},
    isdir = {},

    expand_map = {},
    hostname = "host",

    job_results = {},
    job_commands = {},

    ui_inputs = {},

    deferred = {},
    defer_immediate = opts.defer_immediate ~= false,
  }

  local function ensure_buf(bufnr)
    if not state.bufs[bufnr] then
      state.bufs[bufnr] = {
        lines = {},
        name = "",
        options = {},
        highlights = {},
        extmarks = {},
      }
    end
    return state.bufs[bufnr]
  end

  local function ensure_win(winnr)
    if not state.wins[winnr] then
      state.wins[winnr] = {
        buf = state.current_buf,
        width = 80,
        options = {},
      }
    end
    return state.wins[winnr]
  end

  -- seed a default buffer/window
  ensure_buf(1)
  ensure_win(1)

  local vim = {
    _state = state,
    api = {},
    fn = {},
    ui = {},
    uv = {},
  }

  vim.bo = setmetatable({}, {
    __index = function(_, key)
      if type(key) == "number" then
        return ensure_buf(key).options
      end
      return ensure_buf(state.current_buf).options[key]
    end,
    __newindex = function(_, key, value)
      if type(key) == "number" then
        error("assign buffer options via vim.bo[bufnr].opt")
      end
      ensure_buf(state.current_buf).options[key] = value
    end,
  })

  vim.wo = setmetatable({}, {
    __index = function(_, key)
      if type(key) == "number" then
        return ensure_win(key).options
      end
      return ensure_win(state.current_win).options[key]
    end,
    __newindex = function(_, key, value)
      if type(key) == "number" then
        error("assign window options via vim.wo[winnr].opt")
      end
      ensure_win(state.current_win).options[key] = value
    end,
  })

  function vim.cmd(cmd)
    table.insert(state.cmd_history, cmd)
  end

  function vim.defer_fn(fn, ms)
    table.insert(state.deferred, { fn = fn, ms = ms })
    if state.defer_immediate then
      fn()
    end
  end

  function vim.split(str, sep, _)
    local out = {}
    local patt = string.format("([^%s]*)%s?", sep, sep)
    local last_end = 1
    local s, e, cap = str:find(patt, 1)
    while s do
      if s ~= last_end then
        break
      end
      table.insert(out, cap)
      last_end = e + 1
      if last_end > #str then
        break
      end
      s, e, cap = str:find(patt, last_end)
    end
    return out
  end

  function vim.iter(tbl)
    local wrapper = { _tbl = tbl }
    function wrapper:flatten()
      self._tbl = iter_flatten(self._tbl)
      return self
    end
    function wrapper:totable()
      return iter_flatten(self._tbl)
    end
    return wrapper
  end

  function vim.tbl_deep_extend(_, ...)
    local args = { ... }
    local result = deep_copy(args[1] or {})
    for i = 2, #args do
      deep_extend(result, args[i] or {})
    end
    return result
  end

  vim.uv.fs_stat = function(path)
    return state.files[path] and { type = "file" } or nil
  end

  vim.fn.hostname = function()
    return state.hostname
  end

  vim.fn.expand = function(expr)
    if state.expand_map[expr] ~= nil then
      return state.expand_map[expr]
    end
    return expr
  end

  vim.fn.isdirectory = function(path)
    return state.isdir[path] and 1 or 0
  end

  vim.fn.mkdir = function(path, _)
    state.isdir[path] = true
  end

  vim.fn.readfile = function(path, _)
    return deep_copy(state.files[path] or {})
  end

  vim.fn.writefile = function(lines, path, _)
    state.files[path] = deep_copy(lines)
  end

  vim.fn.fnamemodify = function(path, mod)
    local dir, base = split_path(path)
    if mod == ":t" then
      return base
    elseif mod == ":h" then
      return dir
    end
    return path
  end

  vim.fn.strdisplaywidth = function(str)
    return #str
  end

  vim.fn.jobstart = function(command, opts2)
    local job_id = state.next_job
    state.next_job = state.next_job + 1

    table.insert(state.job_commands, command)

    local result = table.remove(state.job_results, 1) or { exit_code = 0, stdout = {}, stderr = {} }

    if opts2 and opts2.on_stdout then
      for _, chunk in ipairs(result.stdout or {}) do
        opts2.on_stdout(job_id, chunk, "stdout")
      end
    end
    if opts2 and opts2.on_stderr then
      for _, chunk in ipairs(result.stderr or {}) do
        opts2.on_stderr(job_id, chunk, "stderr")
      end
    end
    if opts2 and opts2.on_exit then
      opts2.on_exit(job_id, result.exit_code or 0, "exit")
    end

    return job_id
  end

  vim.fn.jobwait = function(_)
    return { 0 }
  end

  vim.diff = function(_, _, _)
    return state.diff_result or ""
  end

  vim.ui.input = function(_, cb)
    local next_val = table.remove(state.ui_inputs, 1)
    cb(next_val)
  end

  -- nvim api stubs
  vim.api.nvim_create_namespace = function(name)
    local id = state.next_ns
    state.next_ns = state.next_ns + 1
    state.namespaces[id] = name
    return id
  end

  vim.api.nvim_set_hl = function(_, name, spec)
    state.highlights[name] = deep_copy(spec)
  end

  vim.api.nvim_get_hl = function(_, opts2)
    return deep_copy(state.highlights[opts2.name] or {})
  end

  vim.api.nvim_create_buf = function(_, _)
    local id = state.next_buf
    state.next_buf = state.next_buf + 1
    ensure_buf(id)
    return id
  end

  vim.api.nvim_buf_is_valid = function(buf)
    return state.bufs[buf] ~= nil
  end

  vim.api.nvim_win_is_valid = function(win)
    return state.wins[win] ~= nil
  end

  vim.api.nvim_get_current_win = function()
    return state.current_win
  end

  vim.api.nvim_get_current_buf = function()
    return state.current_buf
  end

  vim.api.nvim_win_set_buf = function(win, buf)
    ensure_win(win).buf = buf
    state.current_buf = buf
  end

  vim.api.nvim_win_get_width = function(win)
    return ensure_win(win).width
  end

  vim.api.nvim_buf_set_name = function(buf, name)
    ensure_buf(buf).name = name
  end

  vim.api.nvim_buf_get_name = function(buf)
    return ensure_buf(buf).name
  end

  vim.api.nvim_buf_set_option = function(buf, name, value)
    ensure_buf(buf).options[name] = value
  end

  vim.api.nvim_buf_get_option = function(buf, name)
    return ensure_buf(buf).options[name]
  end

  vim.api.nvim_buf_set_lines = function(buf, start, end_, _, lines)
    local b = ensure_buf(buf)
    if start == 0 and end_ == -1 then
      b.lines = deep_copy(lines)
      return
    end
    local prefix = {}
    for i = 1, start do
      prefix[i] = b.lines[i]
    end
    local suffix = {}
    local s = end_ + 1
    if end_ == -1 then
      s = #b.lines + 1
    end
    for i = s, #b.lines do
      table.insert(suffix, b.lines[i])
    end
    b.lines = prefix
    for _, line in ipairs(lines) do
      table.insert(b.lines, line)
    end
    for _, line in ipairs(suffix) do
      table.insert(b.lines, line)
    end
  end

  vim.api.nvim_buf_get_lines = function(buf, start, end_, _)
    local b = ensure_buf(buf)
    local out = {}
    local from = start + 1
    local to = end_
    if end_ == -1 then
      to = #b.lines
    end
    for i = from, to do
      table.insert(out, b.lines[i])
    end
    return out
  end

  vim.api.nvim_buf_add_highlight = function(buf, _, hl, line, col_start, col_end)
    table.insert(ensure_buf(buf).highlights, {
      hl_group = hl,
      line = line,
      col_start = col_start,
      col_end = col_end,
    })
  end

  vim.api.nvim_buf_set_extmark = function(buf, _, line, col, opts2)
    table.insert(ensure_buf(buf).extmarks, {
      line = line,
      col = col,
      opts = deep_copy(opts2),
    })
  end

  vim.api.nvim_buf_clear_namespace = function(buf, _, _, _)
    local b = ensure_buf(buf)
    b.highlights = {}
    b.extmarks = {}
  end

  vim.api.nvim_create_user_command = function(name, fn, cmd_opts)
    state.user_commands[name] = { fn = fn, opts = deep_copy(cmd_opts) }
  end

  vim.api.nvim_create_augroup = function(name, _)
    local id = #state.augroups + 1
    state.augroups[id] = name
    return id
  end

  vim.api.nvim_create_autocmd = function(event, opts2)
    table.insert(state.autocmds, { event = event, opts = deep_copy(opts2) })
    return #state.autocmds
  end

  function vim._queue_job_result(result)
    table.insert(state.job_results, result)
  end

  function vim._queue_input(val)
    table.insert(state.ui_inputs, val)
  end

  return vim
end

return M
