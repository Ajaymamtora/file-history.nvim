-- Comprehensive diff display scenarios test suite
-- Based on vscode-diff.nvim reference plugin test patterns

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

-- Helper to create unified diff format
local function make_diff(opts)
  local lines = {}
  -- Add standard diff header
  table.insert(lines, "diff --git a/file b/file")
  table.insert(lines, "--- a/file")
  table.insert(lines, "+++ b/file")
  
  if opts.hunk_header then
    table.insert(lines, opts.hunk_header)
  else
    table.insert(lines, "@@ -1,1 +1,1 @@")
  end
  
  for _, line in ipairs(opts.content or {}) do
    table.insert(lines, line)
  end
  
  return table.concat(lines, "\n")
end

describe("Diff Display Scenarios", function()
  local vim
  local preview

  before_each(function()
    vim = test_env.bootstrap()
    preview = require("file_history.preview")
  end)

  -- ============================================================
  -- SECTION 1: parse_diff - Basic Line Classification
  -- ============================================================
  
  describe("parse_diff line classification", function()
    it("classifies added lines and strips prefix", function()
      local diff = "@@ -1,1 +1,2 @@\n context\n+added line"
      local parsed, stats = preview.parse_diff(diff)
      
      local add_line = nil
      for _, line in ipairs(parsed) do
        if line.type == "add" then
          add_line = line
          break
        end
      end
      
      assert.is_not_nil(add_line, "Should have an add line")
      assert.equals("added line", add_line.text, "Prefix should be stripped")
      assert.equals(1, stats.added)
    end)
    
    it("classifies deleted lines and strips prefix", function()
      local diff = "@@ -1,2 +1,1 @@\n context\n-deleted line"
      local parsed, stats = preview.parse_diff(diff)
      
      local del_line = nil
      for _, line in ipairs(parsed) do
        if line.type == "delete" then
          del_line = line
          break
        end
      end
      
      assert.is_not_nil(del_line, "Should have a delete line")
      assert.equals("deleted line", del_line.text, "Prefix should be stripped")
      assert.equals(1, stats.deleted)
    end)
    
    it("classifies context lines and strips leading space", function()
      local diff = "@@ -1,1 +1,1 @@\n context line"
      local parsed = preview.parse_diff(diff)
      
      local ctx_line = nil
      for _, line in ipairs(parsed) do
        if line.type == "context" then
          ctx_line = line
          break
        end
      end
      
      assert.is_not_nil(ctx_line, "Should have a context line")
      assert.equals("context line", ctx_line.text, "Leading space should be stripped")
    end)
  end)

  -- ============================================================
  -- SECTION 2: Empty and Edge Cases
  -- ============================================================
  
  describe("empty and edge cases", function()
    it("handles empty diff text", function()
      local parsed, stats = preview.parse_diff("")
      
      assert.is_table(parsed)
      assert.equals(0, stats.added)
      assert.equals(0, stats.deleted)
      assert.equals(0, stats.hunks)
    end)
    
    it("handles diff with only additions (new file)", function()
      local diff = table.concat({
        "@@ -0,0 +1,3 @@",
        "+line 1",
        "+line 2",
        "+line 3",
      }, "\n")
      
      local parsed, stats = preview.parse_diff(diff)
      
      assert.equals(3, stats.added)
      assert.equals(0, stats.deleted)
      
      -- All non-header lines should be additions
      local add_count = 0
      for _, line in ipairs(parsed) do
        if line.type == "add" then
          add_count = add_count + 1
        end
      end
      assert.equals(3, add_count)
    end)
    
    it("handles diff with only deletions (file deleted)", function()
      local diff = table.concat({
        "@@ -1,3 +0,0 @@",
        "-line 1",
        "-line 2",
        "-line 3",
      }, "\n")
      
      local parsed, stats = preview.parse_diff(diff)
      
      assert.equals(0, stats.added)
      assert.equals(3, stats.deleted)
    end)
    
    it("handles single line file change", function()
      local diff = "@@ -1,1 +1,1 @@\n-old\n+new"
      local parsed, stats = preview.parse_diff(diff)
      
      assert.equals(1, stats.added)
      assert.equals(1, stats.deleted)
    end)
  end)

  -- ============================================================
  -- SECTION 3: Change Position Edge Cases
  -- ============================================================
  
  describe("change position edge cases", function()
    it("handles changes at the very beginning of file", function()
      local diff = table.concat({
        "@@ -1,3 +1,3 @@",
        "-first line old",
        "+first line new",
        " second line",
        " third line",
      }, "\n")
      
      local parsed, stats = preview.parse_diff(diff)
      
      assert.equals(1, stats.added)
      assert.equals(1, stats.deleted)
      
      -- First non-header line should be a delete
      local first_content = nil
      for _, line in ipairs(parsed) do
        if line.type == "delete" or line.type == "add" or line.type == "context" then
          first_content = line
          break
        end
      end
      assert.equals("delete", first_content.type)
      assert.equals("first line old", first_content.text)
    end)
    
    it("handles changes at the very end of file", function()
      local diff = table.concat({
        "@@ -1,3 +1,3 @@",
        " first line",
        " second line",
        "-last line old",
        "+last line new",
      }, "\n")
      
      local parsed, stats = preview.parse_diff(diff)
      
      -- Find the last add/delete lines
      local last_del, last_add
      for _, line in ipairs(parsed) do
        if line.type == "delete" then last_del = line end
        if line.type == "add" then last_add = line end
      end
      
      assert.equals("last line old", last_del.text)
      assert.equals("last line new", last_add.text)
    end)
    
    it("handles multiple non-contiguous hunks", function()
      local diff = table.concat({
        "@@ -1,2 +1,2 @@",
        "-old line 1",
        "+new line 1",
        " context",
        "@@ -10,2 +10,2 @@",
        " more context",
        "-old line 10",
        "+new line 10",
      }, "\n")
      
      local parsed, stats = preview.parse_diff(diff)
      
      assert.equals(2, stats.hunks)
      assert.equals(2, stats.added)
      assert.equals(2, stats.deleted)
    end)
  end)

  -- ============================================================
  -- SECTION 4: Special Content
  -- ============================================================
  
  describe("special content handling", function()
    it("handles whitespace-only changes", function()
      local diff = table.concat({
        "@@ -1,1 +1,1 @@",
        "-  indented",
        "+    indented",
      }, "\n")
      
      local parsed, stats = preview.parse_diff(diff)
      
      assert.equals(1, stats.added)
      assert.equals(1, stats.deleted)
    end)
    
    it("handles lines with special characters", function()
      local diff = table.concat({
        "@@ -1,2 +1,2 @@",
        "-line with 'quotes' and \"double\"",
        "+line with $dollar and `backtick`",
        " normal line",
      }, "\n")
      
      local parsed = preview.parse_diff(diff)
      
      local del_line, add_line
      for _, line in ipairs(parsed) do
        if line.type == "delete" then del_line = line end
        if line.type == "add" then add_line = line end
      end
      
      assert.equals("line with 'quotes' and \"double\"", del_line.text)
      assert.equals("line with $dollar and `backtick`", add_line.text)
    end)
    
    it("handles unicode content", function()
      local diff = table.concat({
        "@@ -1,1 +1,1 @@",
        "-Hello 世界",
        "+Hello 🌍 World",
      }, "\n")
      
      local parsed = preview.parse_diff(diff)
      
      local del_line, add_line
      for _, line in ipairs(parsed) do
        if line.type == "delete" then del_line = line end
        if line.type == "add" then add_line = line end
      end
      
      assert.equals("Hello 世界", del_line.text)
      assert.equals("Hello 🌍 World", add_line.text)
    end)
    
    it("handles very long lines", function()
      local long_content = string.rep("x", 500)
      local diff = "@@ -1,1 +1,1 @@\n-" .. long_content .. "\n+" .. long_content .. "y"
      
      local parsed = preview.parse_diff(diff)
      
      local add_line
      for _, line in ipairs(parsed) do
        if line.type == "add" then add_line = line break end
      end
      
      assert.equals(501, #add_line.text)
    end)
    
    it("handles 'No newline at end of file' markers", function()
      local diff = table.concat({
        "@@ -1,1 +1,1 @@",
        "-old",
        "+new",
        "\\ No newline at end of file",
      }, "\n")
      
      local parsed = preview.parse_diff(diff)
      
      -- No newline marker should be at the end
      local last_line = parsed[#parsed]
      assert.equals("no_newline", last_line.type)
    end)
  end)

  -- ============================================================
  -- SECTION 5: Render Diff - Inline Mode
  -- ============================================================
  
  describe("render_diff inline mode", function()
    it("renders without +/- prefix characters", function()
      preview.setup({ header_style = "none", highlight_style = "text", diff_style = "inline" })
      
      local buf = vim.api.nvim_create_buf(true, true)
      local ctx = new_preview_ctx(vim, buf, 1)
      
      local diff = "@@ -1,1 +1,2 @@\n-old\n+new\n+added"
      preview.render_diff(ctx, diff)
      
      local lines = ctx._preview_state.lines
      
      -- None of the lines should start with + or -
      for _, line in ipairs(lines) do
        assert.is_falsy(line:match("^[%+%-]"), "Line should not start with +/-: " .. line)
      end
    end)
    
    it("applies correct highlight groups", function()
      preview.setup({ header_style = "none", highlight_style = "text", diff_style = "inline" })
      
      local buf = vim.api.nvim_create_buf(true, true)
      local ctx = new_preview_ctx(vim, buf, 1)
      
      local diff = "@@ -1,1 +1,1 @@\n-old\n+new\n context"
      preview.render_diff(ctx, diff)
      
      local highlights = vim._state.bufs[buf].highlights
      
      -- Should have DiffDelete and DiffAdd highlights
      local has_delete = false
      local has_add = false
      for _, hl in ipairs(highlights) do
        if hl.hl_group == "DiffDelete" then has_delete = true end
        if hl.hl_group == "DiffAdd" then has_add = true end
      end
      
      assert.is_true(has_delete, "Should have DiffDelete highlight")
      assert.is_true(has_add, "Should have DiffAdd highlight")
    end)
    
    it("strips context line leading space", function()
      preview.setup({ header_style = "none", highlight_style = "text", diff_style = "inline" })
      
      local buf = vim.api.nvim_create_buf(true, true)
      local ctx = new_preview_ctx(vim, buf, 1)
      
      local diff = "@@ -1,1 +1,1 @@\n context line here"
      preview.render_diff(ctx, diff)
      
      local lines = ctx._preview_state.lines
      assert.equals("context line here", lines[1])
    end)
  end)

  -- ============================================================
  -- ============================================================
  -- SECTION 6: Side by Side Conversion
  -- ============================================================
  
  describe("side_by_side conversion logic", function()
    it("gracefully falls back to inline when window unavailable", function()
      preview.setup({ header_style = "none", highlight_style = "text", diff_style = "side_by_side" })
      
      local buf = vim.api.nvim_create_buf(true, true)
      local ctx = new_preview_ctx(vim, buf, nil) -- nil window
      
      local diff = "@@ -1,1 +1,1 @@\n-old\n+new"
      
      -- Should not crash even with side_by_side requested but no window
      local success = pcall(function()
        preview.render_diff(ctx, diff)
      end)
      
      assert.is_true(success, "Should handle missing window gracefully")
      assert.is_true(#ctx._preview_state.lines > 0, "Should produce inline output")
    end)
    
    it("strips prefixes correctly in fallback mode", function()
      preview.setup({ header_style = "none", highlight_style = "text", diff_style = "side_by_side" })
      
      local buf = vim.api.nvim_create_buf(true, true)
      local ctx = new_preview_ctx(vim, buf, nil)
      
      local diff = "@@ -1,1 +1,1 @@\n-deleted\n+added"
      preview.render_diff(ctx, diff)
      
      local lines = ctx._preview_state.lines
      for _, line in ipairs(lines) do
        assert.is_falsy(line:match("^[%+%-]"), "Should not have raw +/- prefix")
      end
    end)
  end)
  
  -- ============================================================
  -- SECTION 7: Large Diff Performance

  -- ============================================================
  
  describe("large diff handling", function()
    it("handles large number of changes efficiently", function()
      preview.setup({ header_style = "raw", highlight_style = "text", diff_style = "inline" })
      
      local buf = vim.api.nvim_create_buf(true, true)
      local ctx = new_preview_ctx(vim, buf, 1)
      
      -- Create diff with 100 changes
      local lines = { "@@ -1,100 +1,100 @@" }
      for i = 1, 100 do
        table.insert(lines, "-old line " .. i)
        table.insert(lines, "+new line " .. i)
      end
      local diff = table.concat(lines, "\n")
      
      local success = pcall(function()
        preview.render_diff(ctx, diff)
      end)
      
      assert.is_true(success, "Should handle large diffs without error")
      assert.is_true(#ctx._preview_state.lines > 0, "Should produce output")
    end)
    
    it("truncates very large diffs with notification", function()
      preview.setup({ header_style = "raw", highlight_style = "text", diff_style = "inline" })
      
      local buf = vim.api.nvim_create_buf(true, true)
      local ctx = new_preview_ctx(vim, buf, 1)
      
      -- Create diff exceeding MAX_LINES_TOTAL (5000)
      local lines = { "@@ -1,6000 +1,6000 @@" }
      for i = 1, 6000 do
        table.insert(lines, "+line " .. i)
      end
      local diff = table.concat(lines, "\n")
      
      preview.render_diff(ctx, diff)
      
      -- Should have notification about large diff
      assert.is_true(#ctx._preview_state.notify_calls > 0, "Should notify about large diff")
      assert.is_truthy(ctx._preview_state.notify_calls[1].msg:find("Large diff"))
      
      -- Should be truncated
      assert.is_true(#ctx._preview_state.lines <= 5000, "Should truncate to max lines")
    end)
  end)

  -- ============================================================
  -- SECTION 8: Re-rendering
  -- ============================================================
  
  describe("re-rendering behavior", function()
    it("clears previous content on re-render", function()
      preview.setup({ header_style = "none", highlight_style = "text", diff_style = "inline" })
      
      local buf = vim.api.nvim_create_buf(true, true)
      local ctx = new_preview_ctx(vim, buf, 1)
      
      -- First render
      preview.render_diff(ctx, "@@ -1,1 +1,1 @@\n-old\n+new")
      local first_line_count = #ctx._preview_state.lines
      
      -- Second render with different content
      preview.render_diff(ctx, "@@ -1,1 +1,1 @@\n-a\n+b")
      
      -- Reset should have been called
      assert.equals(2, ctx._preview_state.reset_called, "Should call reset on each render")
    end)
  end)
end)
