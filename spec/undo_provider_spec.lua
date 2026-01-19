local test_env = require("helpers.test_env")

describe("undo provider", function()
  local vim
  local undo_provider

  before_each(function()
    vim = test_env.bootstrap()
    _G.vim = vim
    undo_provider = require("file_history.providers.undo")
  end)

  describe("get_history", function()
    it("returns empty list for invalid buffer", function()
      vim.api.nvim_buf_is_valid = function() return false end

      local items = undo_provider.get_history(-1, "/test/file.lua")

      assert.equals(0, #items)
    end)

    it("returns empty list when no undo history exists", function()
      vim.api.nvim_buf_is_valid = function() return true end
      vim.fn.undotree = function() return { entries = {} } end

      local items = undo_provider.get_history(1, "/test/file.lua")

      assert.equals(0, #items)
    end)

    it("converts undo tree entries to history items", function()
      vim.api.nvim_buf_is_valid = function() return true end
      vim.fn.undotree = function()
        return {
          seq_last = 3,
          seq_cur = 3,
          entries = {
            { seq = 1, time = os.time() - 3600 },
            { seq = 2, time = os.time() - 1800, save = 1 },
            { seq = 3, time = os.time() - 60 },
          }
        }
      end

      local items = undo_provider.get_history(1, "/test/file.lua")

      assert.equals(3, #items)
      assert.equals("undo", items[1].source)
      assert.equals(3, items[1].seq)
      assert.equals(2, items[2].seq)
      assert.equals(1, items[3].seq)
      assert.is_true(items[2].is_save_point)
    end)

    it("handles undo branches with alt field", function()
      vim.api.nvim_buf_is_valid = function() return true end
      vim.fn.undotree = function()
        return {
          seq_last = 4,
          seq_cur = 4,
          entries = {
            {
              seq = 2,
              time = os.time() - 1800,
              alt = {
                { seq = 3, time = os.time() - 900 },
              }
            },
            { seq = 4, time = os.time() - 60 },
          }
        }
      end

      local items = undo_provider.get_history(1, "/test/file.lua")

      assert.equals(3, #items)
      local branch_item = nil
      for _, item in ipairs(items) do
        if item.seq == 3 then
          branch_item = item
        end
      end
      assert.is_not_nil(branch_item)
      assert.equals(1, branch_item.branch_depth)
    end)

    it("respects max_entries config", function()
      vim.api.nvim_buf_is_valid = function() return true end
      vim.fn.undotree = function()
        local entries = {}
        for i = 1, 200 do
          table.insert(entries, { seq = i, time = os.time() - i })
        end
        return { seq_last = 200, seq_cur = 200, entries = entries }
      end

      undo_provider.setup({ max_entries = 50 })
      local items = undo_provider.get_history(1, "/test/file.lua")

      assert.is_true(#items <= 50)
    end)

    it("filters to save points only when configured", function()
      vim.api.nvim_buf_is_valid = function() return true end
      vim.fn.undotree = function()
        return {
          seq_last = 3,
          seq_cur = 3,
          entries = {
            { seq = 1, time = os.time() - 3600 },
            { seq = 2, time = os.time() - 1800, save = 1 },
            { seq = 3, time = os.time() - 60 },
          }
        }
      end

      undo_provider.setup({ save_points_only = true })
      local items = undo_provider.get_history(1, "/test/file.lua")

      assert.equals(1, #items)
      assert.is_true(items[1].is_save_point)
    end)
  end)

  describe("can_revert", function()
    it("returns true for valid item with seq and buf", function()
      vim.api.nvim_buf_is_valid = function() return true end

      local item = { seq = 1, buf = 1 }
      assert.is_true(undo_provider.can_revert(item))
    end)

    it("returns false for item without seq", function()
      local item = { buf = 1 }
      assert.is_false(undo_provider.can_revert(item))
    end)

    it("returns false for invalid buffer", function()
      vim.api.nvim_buf_is_valid = function() return false end

      local item = { seq = 1, buf = 1 }
      assert.is_false(undo_provider.can_revert(item))
    end)
  end)

  describe("supports_action", function()
    it("returns true for revert action", function()
      assert.is_true(undo_provider.supports_action("revert"))
    end)

    it("returns true for diff action", function()
      assert.is_true(undo_provider.supports_action("diff"))
    end)

    it("returns false for delete_history action", function()
      assert.is_false(undo_provider.supports_action("delete_history"))
    end)

    it("returns false for purge_history action", function()
      assert.is_false(undo_provider.supports_action("purge_history"))
    end)
  end)

  describe("setup", function()
    it("merges config options", function()
      undo_provider.setup({
        include_branches = false,
        max_entries = 50,
      })

      assert.is_false(undo_provider.config.include_branches)
      assert.equals(50, undo_provider.config.max_entries)
    end)
  end)
end)
