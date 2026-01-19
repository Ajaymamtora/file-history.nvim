local test_env = require("helpers.test_env")

describe("providers", function()
  local vim
  local providers

  before_each(function()
    vim = test_env.bootstrap()
    _G.vim = vim
    providers = require("file_history.providers")
  end)

  describe("register", function()
    it("registers a provider by name", function()
      local mock_provider = {
        get_history = function() return {} end,
        get_content = function() return {} end,
        can_revert = function() return true end,
        revert = function() return true end,
      }

      providers.register("test", mock_provider)

      assert.is_not_nil(providers.providers["test"])
      assert.equals("test", providers.providers["test"].name)
    end)
  end)

  describe("get_history", function()
    it("returns empty list when no providers registered", function()
      providers.providers = {}

      local items = providers.get_history({}, 1, "/test/file.lua")

      assert.equals(0, #items)
    end)

    it("returns items from single provider", function()
      local mock_provider = {
        get_history = function()
          return {
            { id = "1", timestamp = 100, text = "item1" },
            { id = "2", timestamp = 200, text = "item2" },
          }
        end,
      }
      providers.register("mock", mock_provider)

      local items = providers.get_history({ "mock" }, 1, "/test/file.lua")

      assert.equals(2, #items)
      assert.equals("mock", items[1].source)
    end)

    it("merges and sorts items from multiple providers", function()
      local git_provider = {
        get_history = function()
          return {
            { id = "git1", timestamp = 100, text = "git item" },
          }
        end,
      }
      local undo_provider = {
        get_history = function()
          return {
            { id = "undo1", timestamp = 200, text = "undo item" },
          }
        end,
      }
      providers.register("git", git_provider)
      providers.register("undo", undo_provider)

      local items = providers.get_history({ "git", "undo" }, 1, "/test/file.lua")

      assert.equals(2, #items)
      assert.equals("undo1", items[1].id)
      assert.equals("git1", items[2].id)
    end)

    it("handles provider errors gracefully", function()
      local failing_provider = {
        get_history = function()
          error("Provider failed!")
        end,
      }
      providers.register("failing", failing_provider)

      local items = providers.get_history({ "failing" }, 1, "/test/file.lua")

      assert.equals(0, #items)
    end)
  end)

  describe("get_content", function()
    it("returns content from correct provider", function()
      local mock_provider = {
        get_content = function(item)
          return { "line1", "line2" }
        end,
      }
      providers.register("mock", mock_provider)

      local item = { source = "mock", id = "1" }
      local lines = providers.get_content(item)

      assert.equals(2, #lines)
      assert.equals("line1", lines[1])
    end)

    it("returns empty table for unknown source", function()
      local item = { source = "unknown", id = "1" }
      local lines = providers.get_content(item)

      assert.equals(0, #lines)
    end)
  end)

  describe("revert", function()
    it("calls provider revert method", function()
      local revert_called = false
      local mock_provider = {
        can_revert = function() return true end,
        revert = function(item, buf)
          revert_called = true
          return true
        end,
      }
      providers.register("mock", mock_provider)

      local item = { source = "mock", id = "1" }
      local result = providers.revert(item, 1)

      assert.is_true(revert_called)
      assert.is_true(result)
    end)

    it("returns false when provider cannot revert", function()
      local mock_provider = {
        can_revert = function() return false end,
        revert = function() return true end,
      }
      providers.register("mock", mock_provider)

      local item = { source = "mock", id = "1" }
      local result = providers.revert(item, 1)

      assert.is_false(result)
    end)
  end)

  describe("supports_action", function()
    it("returns true for supported actions", function()
      local mock_provider = {
        supports_action = function(action)
          return action == "revert"
        end,
      }
      providers.register("mock", mock_provider)

      local item = { source = "mock" }
      assert.is_true(providers.supports_action(item, "revert"))
      assert.is_false(providers.supports_action(item, "delete"))
    end)

    it("returns true by default when no supports_action defined", function()
      local mock_provider = {}
      providers.register("mock", mock_provider)

      local item = { source = "mock" }
      assert.is_true(providers.supports_action(item, "any_action"))
    end)
  end)

  describe("get_provider_names", function()
    it("returns list of registered provider names", function()
      providers.providers = {}
      providers.register("git", {})
      providers.register("undo", {})

      local names = providers.get_provider_names()

      assert.equals(2, #names)
      local has_git, has_undo = false, false
      for _, name in ipairs(names) do
        if name == "git" then has_git = true end
        if name == "undo" then has_undo = true end
      end
      assert.is_true(has_git)
      assert.is_true(has_undo)
    end)
  end)
end)
