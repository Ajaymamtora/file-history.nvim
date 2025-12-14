local test_env = require("helpers.test_env")

local function last_cmd(vim)
  return vim._state.cmd_history[#vim._state.cmd_history]
end

describe("file_history.actions", function()
  local vim
  local actions

  before_each(function()
    vim = test_env.bootstrap()
    vim._state.expand_map["~/.fh"] = "/home/me/.fh"

    -- ensure plenary.filetype stub is used
    actions = require("file_history.actions")
  end)

  it("revert_to_selected no-ops when data.buf missing", function()
    actions.revert_to_selected({ file = "/tmp/a", hash = "H" }, {})
  end)

  it("revert_to_selected replaces buffer lines", function()
    local fh = require("file_history.fh")
    fh.setup({ backup_dir = "~/.fh", hostname = "myhost" })

    vim._queue_job_result({ exit_code = 0, stdout = { { "a", "b" } }, stderr = {} })

    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "x" })

    actions.revert_to_selected({ file = "/tmp/a", hash = "H" }, { buf = buf })

    assert.are.same({ "a", "b" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)

  it("delete_history deletes all selected items", function()
    local fh = require("file_history.fh")
    fh.setup({ backup_dir = "~/.fh", hostname = "myhost" })

    -- No queued jobs needed; delete_file ignores output.
    local picker = {
      selected = function()
        return { { name = "host/a" }, { name = "host/b" } }
      end,
    }

    actions.delete_history(picker)

    -- should have invoked git rm twice
    local cmd1 = table.concat(vim._state.job_commands[#vim._state.job_commands - 1], " ")
    local cmd2 = table.concat(vim._state.job_commands[#vim._state.job_commands], " ")
    assert.is_truthy(cmd1:match("rm"))
    assert.is_truthy(cmd2:match("rm"))
  end)

  it("purge_history purges all selected items", function()
    local fh = require("file_history.fh")
    fh.setup({ backup_dir = "~/.fh", hostname = "myhost" })

    local picker = {
      selected = function()
        return { { name = "host/a" } }
      end,
    }

    actions.purge_history(picker)

    local cmd = table.concat(vim._state.job_commands[#vim._state.job_commands], " ")
    assert.is_truthy(cmd:match("filter%-repo"))
  end)

  it("open_selected_file_hash_in_new_tab detects filetype and opens buffer", function()
    local fh = require("file_history.fh")
    fh.setup({ backup_dir = "~/.fh", hostname = "myhost" })

    vim._queue_job_result({ exit_code = 0, stdout = { { "line" } }, stderr = {} })

    actions.open_selected_file_hash_in_new_tab({ file = "/tmp/test.lua", hash = "H" })

    assert.equals("tabnew", last_cmd(vim))

    local plenary = require("plenary.filetype")
    assert.are.same({ file = "/tmp/test.lua", opts = {} }, plenary.last_detect)

    -- should have created a new buffer and set name to hash:file
    local created = vim._state.next_buf - 1
    assert.equals("H:/tmp/test.lua", vim.api.nvim_buf_get_name(created))
    assert.equals("lua", vim.api.nvim_buf_get_option(created, "filetype"))
    assert.is_false(vim.api.nvim_buf_get_option(created, "modifiable"))
  end)

  it("open_selected_hash_in_new_tab uses current buffer filetype", function()
    local fh = require("file_history.fh")
    fh.setup({ backup_dir = "~/.fh", hostname = "myhost" })

    vim._queue_job_result({ exit_code = 0, stdout = { { "line" } }, stderr = {} })

    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_option(buf, "filetype", "python")

    actions.open_selected_hash_in_new_tab({ file = "/tmp/a.py", hash = "H" }, { buf = buf })

    local created = vim._state.next_buf - 1
    assert.equals("python", vim.api.nvim_buf_get_option(created, "filetype"))
  end)

  it("open_buffer_diff_tab opens tab, splits and runs diffthis", function()
    local fh = require("file_history.fh")
    fh.setup({ backup_dir = "~/.fh", hostname = "myhost" })

    vim._queue_job_result({ exit_code = 0, stdout = { { "a" } }, stderr = {} })

    local buf = vim.api.nvim_get_current_buf()
    actions.open_buffer_diff_tab({ file = "/tmp/a", hash = "H" }, { buf = buf })

    local cmds = table.concat(vim._state.cmd_history, "\n")
    assert.is_truthy(cmds:match("tabnew"))
    assert.is_truthy(cmds:match("vsplit"))
    assert.is_truthy(cmds:match("windo diffthis"))
  end)

  it("open_file_diff_tab opens diff between HEAD and selected hash", function()
    local fh = require("file_history.fh")
    fh.setup({ backup_dir = "~/.fh", hostname = "myhost" })

    -- create_buffer_for_file called twice => two git show results
    vim._queue_job_result({ exit_code = 0, stdout = { { "head" } }, stderr = {} })
    vim._queue_job_result({ exit_code = 0, stdout = { { "old" } }, stderr = {} })

    actions.open_file_diff_tab({ file = "/tmp/a", hash = "H" })

    local cmds = table.concat(vim._state.cmd_history, "\n")
    assert.is_truthy(cmds:match("tabnew"))
    assert.is_truthy(cmds:match("vsplit"))
    assert.is_truthy(cmds:match("windo diffthis"))
  end)
end)
