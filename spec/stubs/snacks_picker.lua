local M = {
  last_pick = nil,
}

M.preview = {
  file = function(ctx)
    ctx.preview:reset()
    ctx.preview:set_lines({ "FILE:" .. (ctx.item.file or "") })
  end,
}

function M.pick(spec)
  M.last_pick = spec
  return spec
end

return M
