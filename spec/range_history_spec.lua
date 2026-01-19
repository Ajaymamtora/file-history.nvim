local test_env = require("helpers.test_env")

describe("file_history.range_utils", function()
  local vim
  local file_history

  before_each(function()
    vim = test_env.bootstrap()
    file_history = require("file_history")
  end)

  describe("parse_hunk_header", function()
    it("parses standard hunk header", function()
      local result = file_history.parse_hunk_header("@@ -10,5 +12,7 @@")
      assert.are.same({old_start = 10, old_count = 5, new_start = 12, new_count = 7}, result)
    end)

    it("defaults count to 1 when omitted", function()
      local result = file_history.parse_hunk_header("@@ -3 +5 @@")
      assert.are.same({old_start = 3, old_count = 1, new_start = 5, new_count = 1}, result)
    end)

    it("ignores trailing context text", function()
      local result = file_history.parse_hunk_header("@@ -10,5 +12,7 @@ function foo()")
      assert.are.same({old_start = 10, old_count = 5, new_start = 12, new_count = 7}, result)
    end)

    it("returns nil for malformed input", function()
      local result = file_history.parse_hunk_header("not a hunk header")
      assert.is_nil(result)
    end)

    it("handles zero count", function()
      local result = file_history.parse_hunk_header("@@ -1,0 +1,2 @@")
      assert.are.same({old_start = 1, old_count = 0, new_start = 1, new_count = 2}, result)
    end)
  end)

  describe("diff_affects_range", function()
    it("returns true when hunk overlaps range", function()
      local diff = "@@ -10,5 +10,5 @@\n-old\n+new"
      local result = file_history.diff_affects_range(diff, 12, 15)
      assert.is_true(result)
    end)

    it("returns false when hunk is before range", function()
      local diff = "@@ -1,3 +1,3 @@\n-old\n+new"
      local result = file_history.diff_affects_range(diff, 10, 20)
      assert.is_false(result)
    end)

    it("returns false when hunk is after range", function()
      local diff = "@@ -50,3 +50,3 @@\n-old\n+new"
      local result = file_history.diff_affects_range(diff, 10, 20)
      assert.is_false(result)
    end)

    it("returns true when hunk touches range boundary", function()
      local diff = "@@ -10,5 +10,5 @@\n-old\n+new"
      local result = file_history.diff_affects_range(diff, 14, 20)
      assert.is_true(result)
    end)

    it("returns false for empty diff", function()
      local result = file_history.diff_affects_range("", 10, 20)
      assert.is_false(result)
    end)

    it("returns true when any hunk matches in multi-hunk diff", function()
      local diff = "@@ -1,3 +1,3 @@\n-a\n+b\n@@ -50,3 +50,3 @@\n-c\n+d"
      local result = file_history.diff_affects_range(diff, 50, 55)
      assert.is_true(result)
    end)
  end)

  describe("filter_diff_to_range", function()
    it("returns only hunks within range", function()
      local diff = "@@ -1,3 +1,3 @@\n-a\n+b\n context\n@@ -50,3 +50,3 @@\n-c\n+d\n context2"
      local result = file_history.filter_diff_to_range(diff, 50, 55)
      assert.is_not_nil(result:match("@@ %-50,3"))
      assert.is_nil(result:match("@@ %-1,3"))
    end)

    it("returns empty string when no hunks in range", function()
      local diff = "@@ -1,3 +1,3 @@\n-a\n+b"
      local result = file_history.filter_diff_to_range(diff, 50, 55)
      assert.equals("", result)
    end)

    it("includes full hunk content", function()
      local diff = "@@ -10,3 +10,3 @@\n-old line\n+new line\n context line"
      local result = file_history.filter_diff_to_range(diff, 10, 15)
      assert.is_not_nil(result:match("%-old line"))
      assert.is_not_nil(result:match("%+new line"))
      assert.is_not_nil(result:match("context line"))
    end)

    it("handles empty diff", function()
      local result = file_history.filter_diff_to_range("", 10, 20)
      assert.equals("", result)
    end)
  end)

  describe("prepare_picker_data_range", function()
    it("returns data structure with range", function()
      local data = file_history.prepare_picker_data_range(10, 20)
      assert.is_not_nil(data.range)
      assert.equals(10, data.range.start_line)
      assert.equals(20, data.range.end_line)
    end)

    it("includes buf and buf_lines fields", function()
      local data = file_history.prepare_picker_data_range(1, 5)
      assert.is_not_nil(data.buf)
      assert.is_not_nil(data.buf_lines)
      assert.is_false(data.log)
    end)
  end)
end)
