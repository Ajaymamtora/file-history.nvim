local test_env = require("helpers.test_env")

local function make_ctx(vim, buf, win)
  local preview_state = { lines = nil, reset_called = 0 }
  local preview_obj = {
    reset = function()
      preview_state.reset_called = preview_state.reset_called + 1
    end,
    set_lines = function(_, lines)
      preview_state.lines = lines
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    end,
    notify = function() end,
  }

  return {
    buf = buf,
    win = win,
    preview = preview_obj,
    item = {},
    _preview_state = preview_state,
  }
end

describe("file_history.init", function()
  local vim

  before_each(function()
    vim = test_env.bootstrap()
    vim._state.expand_map["%:p:h"] = "/tmp"
    vim._state.expand_map["%:t"] = "a.lua"
  end)

  it("setup loads snacks picker and registers :FileHistory command", function()
    local mod = require("file_history")
    mod.setup({ backup_dir = "~/.fh" })

    assert.is_table(vim._state.user_commands.FileHistory)
    assert.equals(1, vim._state.user_commands.FileHistory.opts.nargs)

    -- highlight default links should have been issued
    local cmd_text = table.concat(vim._state.cmd_history, "\n")
    assert.is_truthy(cmd_text:match("highlight default link FileHistoryTime"))
  end)

  it("setup uses histogram algorithm and linematch by default", function()
    local mod = require("file_history")
    mod.setup({ backup_dir = "~/.fh" })

    -- Verify default diff_opts are set correctly
    assert.equals("histogram", mod.opts.diff_opts.algorithm)
    assert.equals(60, mod.opts.diff_opts.linematch)
    assert.equals("unified", mod.opts.diff_opts.result_type)
    assert.equals(3, mod.opts.diff_opts.ctxlen)
  end)

  it("allows overriding diff_opts in setup", function()
    local mod = require("file_history")
    mod.setup({
      backup_dir = "~/.fh",
      diff_opts = {
        algorithm = "patience",
        linematch = 100,
      }
    })

    assert.equals("patience", mod.opts.diff_opts.algorithm)
    assert.equals(100, mod.opts.diff_opts.linematch)
  end)

  it("history() triggers snacks picker with expected title and keys", function()
    local mod = require("file_history")
    mod.setup({ backup_dir = "~/.fh" })

    -- fake file history output
    local fh = require("file_history.fh")
    vim._queue_job_result({
      exit_code = 0,
      stdout = { { "1h\t2025-01-01\tHASH\t/tmp/a.lua\ttag" } },
      stderr = {},
    })

    -- buffer data used by preview
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "cur" })
    vim.api.nvim_buf_set_name(buf, "/tmp/a.lua")

    mod.history()

    local picker = require("snacks.picker")
    assert.is_table(picker.last_pick)
    assert.equals("FileHistory history", picker.last_pick.win.title)

    assert.is_table(picker.last_pick.win.input.keys[mod.opts.key_bindings.open_buffer_diff_tab])
    assert.is_table(picker.last_pick.win.input.keys[mod.opts.key_bindings.open_snapshot_tab])
    assert.is_table(picker.last_pick.win.input.keys[mod.opts.key_bindings.yank_additions])
    assert.is_table(picker.last_pick.win.input.keys[mod.opts.key_bindings.yank_deletions])

    local items = picker.last_pick.finder({})
    assert.equals(1, #items)
    assert.equals("HASH", items[1].hash)
    assert.equals("/tmp/a.lua", items[1].file)
    assert.equals("tag", items[1].label)

    -- invoking confirm now reverts buffer to selected snapshot content
    vim._queue_job_result({ exit_code = 0, stdout = { { "snap" } }, stderr = {} })
    local mock_picker = { close = function() end }
    picker.last_pick.confirm(mock_picker, items[1])
    -- Buffer should now have the snapshot content
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.equals("snap", lines[1])
  end)

  it("files() picker disables preview when path missing", function()
    local mod = require("file_history")
    mod.setup({ backup_dir = "~/.fh" })

    -- fake list_files output from git
    local fh = require("file_history.fh")
    vim._queue_job_result({
      exit_code = 0,
      stdout = { { "otherhost/tmp/a.lua" } },
      stderr = {},
    })

    mod.files()
    local picker = require("snacks.picker")

    local items = picker.last_pick.finder({})
    assert.equals(1, #items)
    assert.is_nil(items[1].file)
    assert.equals("otherhost/tmp/a.lua", items[1].text)

    local buf = vim.api.nvim_create_buf(true, true)
    local ctx = make_ctx(vim, buf, 1)
    ctx.item = items[1]

    picker.last_pick.preview(ctx)
    assert.equals(1, ctx._preview_state.reset_called)
  end)

  it("query() builds picker and uses file diff when log toggled", function()
    local mod = require("file_history")
    mod.setup({ backup_dir = "~/.fh" })

    -- ui input: after, before
    vim._queue_input("yesterday")
    vim._queue_input("today")

    -- query finder output
    local fh = require("file_history.fh")
    vim._queue_job_result({
      exit_code = 0,
      stdout = { { "2025-01-01\tHASH\t/tmp/a.lua\ttag" } },
      stderr = {},
    })

    -- preview: HEAD file and parent (for vim.diff)
    vim._queue_job_result({ exit_code = 0, stdout = { { "cur" } }, stderr = {} })
    vim._queue_job_result({ exit_code = 0, stdout = { { "old" } }, stderr = {} })
    vim._state.diff_result = "@@ -1 +1 @@\n-old\n+cur"

    vim._state.files["/tmp/a.lua"] = { "cur" }

    mod.query()

    local picker = require("snacks.picker")
    assert.equals("FileHistory query", picker.last_pick.win.title)

    local item = picker.last_pick.items[1]
    assert.equals("HASH", item.hash)

    -- preview with existing file should render diff
    vim._state.files["/tmp/a.lua"] = { "cur" }
    vim._state.diff_result = "@@ -1 +1 @@\n-old\n+cur"

    local buf = vim.api.nvim_create_buf(true, true)
    local ctx = make_ctx(vim, buf, 1)
    ctx.item = item

    picker.last_pick.preview(ctx)

    local joined = table.concat(ctx._preview_state.lines, "\n")
    assert.is_truthy(joined:match("Changes:"))

    -- toggle incremental to log mode => preview refresh path
    local picker_obj = { preview = { refresh = function() end } }
    picker.last_pick.actions.toggle_incremental(picker_obj)
  end)
end)
