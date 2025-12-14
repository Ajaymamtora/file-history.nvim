local VimStub = require("stubs.vim")

local M = {}

local function reset_loaded(mod_names)
  for _, name in ipairs(mod_names) do
    package.loaded[name] = nil
  end
end

function M.new_vim(opts)
  return VimStub.new(opts)
end

function M.reset_plugin_modules()
  reset_loaded({
    "file_history",
    "file_history.init",
    "file_history.fh",
    "file_history.preview",
    "file_history.actions",
    "snacks",
    "snacks.picker",
    "plenary.filetype",
  })
end

function M.install_stubs()
  package.preload["snacks"] = function()
    return require("stubs.snacks")
  end

  package.preload["snacks.picker"] = function()
    return require("stubs.snacks_picker")
  end

  package.preload["plenary.filetype"] = function()
    return require("stubs.plenary_filetype")
  end
end

function M.bootstrap(opts)
  M.reset_plugin_modules()
  M.install_stubs()

  local vim = M.new_vim(opts)
  _G.vim = vim
  _G.Snacks = require("stubs.snacks")

  return vim
end

return M
