local M = {
  last_detect = nil,
}

function M.detect(file, opts)
  M.last_detect = { file = file, opts = opts }
  return "lua"
end

return M
