local test_env = require("helpers.test_env")

describe("file_history.fh", function()
  local vim
  local fh

  before_each(function()
    vim = test_env.bootstrap()

    -- Set default expansions used by fh.lua
    vim._state.expand_map["%:p:h"] = "/tmp/project"
    vim._state.expand_map["%:t"] = "file.lua"
    vim._state.expand_map["~/.fh"] = "/home/me/.fh"

    fh = require("file_history.fh")
  end)

  it("setup initializes FileHistory and creates autocmd", function()
    fh.setup({ backup_dir = "~/.fh", git_cmd = "git", hostname = "myhost" })

    assert.equals(1, #vim._state.autocmds)
    local ac = vim._state.autocmds[1]
    assert.are.same({ "BufWritePost" }, ac.event)
    assert.is_function(ac.opts.callback)

    -- ensure augroup created
    assert.equals("file_history_group", vim._state.augroups[ac.opts.group])
  end)

  it("autocmd callback ignores non-empty buftype", function()
    fh.setup({ backup_dir = "~/.fh", hostname = "myhost" })

    -- non-empty buffer type should short-circuit
    vim.bo[vim.api.nvim_get_current_buf()].buftype = "nofile"
    vim._state.job_commands = {}

    local cb = vim._state.autocmds[1].opts.callback
    cb()

    assert.equals(0, #vim._state.job_commands)
  end)

  it("autocmd callback triggers backup_file on normal buffers", function()
    fh.setup({ backup_dir = "~/.fh", hostname = "myhost" })

    vim.bo[vim.api.nvim_get_current_buf()].buftype = ""

    local basedir = "/home/me/.fh/"
    vim._state.isdir[basedir .. ".git"] = true

    -- During backup: add; diff-index
    vim._queue_job_result({ exit_code = 0, stdout = {}, stderr = {} }) -- add
    vim._queue_job_result({ exit_code = 0, stdout = {}, stderr = {} }) -- diff-index

    vim._state.files["/tmp/project/file.lua"] = { "a", "b" }

    local cb = vim._state.autocmds[1].opts.callback
    cb()

    assert.is_true(#vim._state.job_commands >= 2)

    -- Ensure writefile called to backuppath includes hostname and dirname
    local backuppath = basedir .. "myhost" .. "/tmp/project" .. "/file.lua"
    assert.are.same({ "a", "b" }, vim._state.files[backuppath])
  end)

  it("file_history returns stdout from git log", function()
    fh.setup({ backup_dir = "~/.fh", hostname = "myhost" })

    vim._queue_job_result({
      exit_code = 0,
      stdout = { { "t\tdate\thash\tmsg" } },
      stderr = {},
    })

    local out = fh.file_history()
    assert.are.same({ { "t\tdate\thash\tmsg" } }, out)
  end)

  it("file_history_files returns stdout from git ls-files", function()
    fh.setup({ backup_dir = "~/.fh", hostname = "myhost" })

    vim._queue_job_result({
      exit_code = 0,
      stdout = { { "myhost/tmp/project/file.lua" } },
      stderr = {},
    })

    local out = fh.file_history_files()
    assert.are.same({ { "myhost/tmp/project/file.lua" } }, out)
  end)

  it("file_history_query passes through after/before and returns stdout", function()
    fh.setup({ backup_dir = "~/.fh", hostname = "myhost" })

    vim._queue_job_result({
      exit_code = 0,
      stdout = { { "2025-01-01\thash\tmsg" } },
      stderr = {},
    })

    local out = fh.file_history_query("yesterday", "today")
    assert.are.same({ { "2025-01-01\thash\tmsg" } }, out)

    local cmd = vim._state.job_commands[#vim._state.job_commands]
    local cmd_str = table.concat(cmd, " ")
    assert.is_truthy(cmd_str:match("%-%-after=yesterday"))
    assert.is_truthy(cmd_str:match("%-%-before=today"))
  end)

  it("get_file flattens stdout to a list of lines", function()
    fh.setup({ backup_dir = "~/.fh", hostname = "myhost" })

    vim._queue_job_result({
      exit_code = 0,
      stdout = { { "line1", "line2" } },
      stderr = {},
    })

    local lines = fh.get_file("/tmp/project/file.lua", "HASH")
    assert.are.same({ "line1", "line2" }, lines)
  end)

  it("get_log flattens stdout to a list of lines", function()
    fh.setup({ backup_dir = "~/.fh", hostname = "myhost" })

    vim._queue_job_result({
      exit_code = 0,
      stdout = { { "diff --git" }, { "+a" } },
      stderr = {},
    })

    local lines = fh.get_log("/tmp/project/file.lua", "HASH")
    assert.are.same({ "diff --git", "+a" }, lines)
  end)

  it("backup_file commits and resets tag when diff-index indicates changes", function()
    fh.setup({ backup_dir = "~/.fh", hostname = "myhost" })

    vim._state.files["/tmp/project/file.lua"] = { "x" }
    vim._state.isdir["/home/me/.fh/.git"] = true

    vim.bo[vim.api.nvim_get_current_buf()].buftype = ""

    fh.set_tag("checkpoint")

    -- add
    vim._queue_job_result({ exit_code = 0, stdout = {}, stderr = {} })
    -- diff-index: non-zero means changes exist
    vim._queue_job_result({ exit_code = 1, stdout = {}, stderr = {} })
    -- commit
    vim._queue_job_result({ exit_code = 0, stdout = {}, stderr = {} })

    -- call the autocmd callback which triggers snapshotting
    local cb
    fh.setup({ backup_dir = "~/.fh", hostname = "myhost" })
    cb = vim._state.autocmds[#vim._state.autocmds].opts.callback
    cb()

    -- ensure commit message contains tag (tab-separated)
    local commit_cmd = vim._state.job_commands[#vim._state.job_commands]
    local cmd_str = table.concat(commit_cmd, " ")
    assert.is_truthy(cmd_str:match("commit"))
    assert.is_truthy(cmd_str:match("/tmp/project/file.lua"))
    assert.is_truthy(cmd_str:match("checkpoint"))

    -- verify that tag is one-shot by triggering another backup and
    -- ensuring the second commit message does not include the tag.
    vim._queue_job_result({ exit_code = 0, stdout = {}, stderr = {} }) -- add
    vim._queue_job_result({ exit_code = 1, stdout = {}, stderr = {} }) -- diff-index
    vim._queue_job_result({ exit_code = 0, stdout = {}, stderr = {} }) -- commit

    cb()

    local second_commit = vim._state.job_commands[#vim._state.job_commands]
    local second_str = table.concat(second_commit, " ")
    assert.is_truthy(second_str:match("commit"))
    assert.is_falsy(second_str:match("checkpoint"))
  end)
end)
