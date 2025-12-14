local test_env = require("helpers.test_env")

local function new_preview_ctx(vim, buf, win)
  local preview_state = {
    reset_called = 0,
    notify_calls = {},
    lines = nil,
  }

  local preview = {
    reset = function()
      preview_state.reset_called = preview_state.reset_called + 1
    end,
    notify = function(_, msg, level)
      table.insert(preview_state.notify_calls, { msg = msg, level = level })
    end,
    set_lines = function(_, lines)
      preview_state.lines = lines
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    end,
  }

  return {
    buf = buf,
    win = win,
    preview = preview,
    item = {},
    _preview_state = preview_state,
  }
end

describe("file_history.preview", function()
  local vim
  local preview

  before_each(function()
    vim = test_env.bootstrap()
    preview = require("file_history.preview")
  end)

  it("parse_diff classifies diff lines and counts stats", function()
    local diff = table.concat({
      "diff --git a/a b/a",
      "index 000..111 100644",
      "--- a/a",
      "+++ b/a",
      "@@ -1,1 +1,2 @@",
      "-old",
      "+new",
      "+new2",
      " context",
      "\\ No newline at end of file",
    }, "\n")

    local parsed, stats = preview.parse_diff(diff)

    assert.equals(10, #parsed) -- no newline marker is moved to end; still counted
    assert.equals("header", parsed[1].type)
    assert.equals("header", parsed[5].type)
    assert.equals("delete", parsed[6].type)
    assert.equals("add", parsed[7].type)
    assert.equals("add", parsed[8].type)
    assert.equals("context", parsed[9].type)

    -- marker becomes last
    assert.equals("no_newline", parsed[#parsed].type)

    assert.are.same({ hunks = 1, added = 2, deleted = 1 }, stats)

    -- hunk header parse info
    assert.is_table(parsed[5].hunk_info)
    assert.equals(1, parsed[5].hunk_info.old_start)
    assert.equals(1, parsed[5].hunk_info.old_count)
    assert.equals(1, parsed[5].hunk_info.new_start)
    assert.equals(2, parsed[5].hunk_info.new_count)
  end)

  it("parse_diff defaults counts to 1 when omitted in hunk header", function()
    local diff = "@@ -3 +5 @@\n-old\n+new"
    local parsed = select(1, preview.parse_diff(diff))
    local hunk = parsed[1]
    assert.equals("header", hunk.type)
    assert.are.same({ old_start = 3, old_count = 1, new_start = 5, new_count = 1 }, hunk.hunk_info)
  end)

  it("get_diff_stats returns added/deleted/changed", function()
    local diff = "@@ -1,1 +1,1 @@\n-old\n+new"
    local stats = preview.get_diff_stats(diff)
    assert.are.same({ added = 1, deleted = 1, changed = 1 }, stats)
  end)

  it("render_diff with header_style=text collapses raw headers", function()
    preview.setup({ header_style = "text", highlight_style = "text" })

    local buf = vim.api.nvim_create_buf(true, true)
    local ctx = new_preview_ctx(vim, buf, 1)

    local diff = table.concat({
      "diff --git a/a b/a",
      "--- a/a",
      "+++ b/a",
      "@@ -1,1 +1,1 @@",
      "-old",
      "+new",
    }, "\n")

    preview.render_diff(ctx, diff, "/tmp/a")

    -- file header is 3 lines prepended
    assert.equals("", ctx._preview_state.lines[1])
    assert.is_truthy(ctx._preview_state.lines[2]:match("/tmp/a"))
    assert.equals("", ctx._preview_state.lines[3])

    -- "Changes:" header present and raw patch headers removed
    local joined = table.concat(ctx._preview_state.lines, "\n")
    assert.is_truthy(joined:match("Changes:"))
    assert.is_falsy(joined:match("diff %-%-git"))
    assert.is_falsy(joined:match("%+%+%+"))
    assert.is_falsy(joined:match("%-%-%-"))
  end)

  it("render_diff with header_style=none removes all headers", function()
    preview.setup({ header_style = "none", highlight_style = "text" })

    local buf = vim.api.nvim_create_buf(true, true)
    local ctx = new_preview_ctx(vim, buf, 1)

    local diff = table.concat({
      "diff --git a/a b/a",
      "@@ -1,1 +1,1 @@",
      "-old",
      "+new",
    }, "\n")

    preview.render_diff(ctx, diff)
    assert.are.same({ "-old", "+new" }, ctx._preview_state.lines)
  end)

  it("render_diff respects show_no_newline=false", function()
    preview.setup({ header_style = "raw", highlight_style = "text", show_no_newline = false })

    local buf = vim.api.nvim_create_buf(true, true)
    local ctx = new_preview_ctx(vim, buf, 1)

    local diff = "+a\n\\ No newline at end of file\n"
    preview.render_diff(ctx, diff)

    local joined = table.concat(ctx._preview_state.lines, "\n")
    assert.is_falsy(joined:match("No newline at end of file"))
  end)

  it("highlight_diff applies expected highlight groups", function()
    preview.setup({ highlight_style = "text" })

    local buf = vim.api.nvim_create_buf(true, true)
    local win = 1

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "+a",
      "-b",
      "@@ -1 +1 @@",
      "\\ No newline at end of file",
      " context",
    })

    local parsed = {
      { type = "add", text = "+a" },
      { type = "delete", text = "-b" },
      { type = "header", text = "@@ -1 +1 @@" },
      { type = "no_newline", text = "\\ No newline at end of file" },
      { type = "context", text = " context" },
    }

    preview.highlight_diff(buf, parsed, win)

    local highlights = vim._state.bufs[buf].highlights
    assert.equals(4, #highlights)
    assert.equals("DiffAdd", highlights[1].hl_group)
    assert.equals("DiffDelete", highlights[2].hl_group)
    assert.equals("DiffChange", highlights[3].hl_group)
    assert.equals("FileHistoryNoNewline", highlights[4].hl_group)
  end)

  it("highlight_diff with highlight_style=full creates extmarks overlays", function()
    preview.setup({ highlight_style = "full" })

    local buf = vim.api.nvim_create_buf(true, true)
    local win = 1

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "+a" })

    preview.highlight_diff(buf, { { type = "add", text = "+a" } }, win)

    assert.equals(1, #vim._state.bufs[buf].extmarks)
    assert.are.same("overlay", vim._state.bufs[buf].extmarks[1].opts.virt_text_pos)
  end)

  it("render_diff truncates large diffs and notifies", function()
    preview.setup({ header_style = "raw", highlight_style = "text" })

    local buf = vim.api.nvim_create_buf(true, true)
    local ctx = new_preview_ctx(vim, buf, 1)

    local lines = {}
    for i = 1, 6000 do
      lines[i] = "+line" .. i
    end
    local diff = table.concat(lines, "\n")

    preview.render_diff(ctx, diff)

    assert.is_true(#ctx._preview_state.lines <= 5000)
    assert.equals(1, #ctx._preview_state.notify_calls)
    assert.is_truthy(ctx._preview_state.notify_calls[1].msg:match("Large diff"))
  end)

  it("render_diff uses deferred highlighting for medium diffs", function()
    vim = test_env.bootstrap({ defer_immediate = false })
    preview = require("file_history.preview")

    preview.setup({ header_style = "raw", highlight_style = "text" })

    local buf = vim.api.nvim_create_buf(true, true)
    local ctx = new_preview_ctx(vim, buf, 1)

    local lines = { "@@ -1 +1 @@" }
    for i = 1, 600 do
      table.insert(lines, "+l" .. i)
    end
    local diff = table.concat(lines, "\n")

    preview.render_diff(ctx, diff)

    -- should have deferred function queued
    assert.equals(1, #vim._state.deferred)
    assert.equals(50, vim._state.deferred[1].ms)

    -- and no highlights yet
    assert.equals(0, #vim._state.bufs[buf].highlights)

    -- run defer we captured
    vim._state.deferred[1].fn()
    assert.is_true(#vim._state.bufs[buf].highlights > 0)
  end)
end)
