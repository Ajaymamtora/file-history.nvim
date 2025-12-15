-- Custom preview module for file-history.nvim
-- Provides highlighted diff previews similar to snacks.nvim

local M = {}

-- Require snacks for icon support
local has_snacks, Snacks = pcall(require, "snacks")
if not has_snacks then
  error("This plugin requires folke/snacks.nvim")
end

local ns = vim.api.nvim_create_namespace("file_history.preview")

-- Set up custom highlight group for "No newline at end of file" markers
vim.api.nvim_set_hl(0, "FileHistoryNoNewline", {
  link = "NonText",
  default = true
})

-- Default options
M.opts = {
  header_style = "text", -- "text", "raw", or "none"
  highlight_style = "full", -- "full" or "text" - whether to extend highlights to full line width
  wrap = true, -- whether to wrap lines in preview
  show_no_newline = true, -- whether to show "\ No newline at end of file" markers
  diff_style = "inline", -- "inline" or "side_by_side"
}

-- Performance thresholds
local PERF = {
  MAX_LINES_INSTANT = 500,    -- Render instantly if diff is smaller
  MAX_LINES_DEFERRED = 2000,  -- Defer rendering if between 500-2000
  MAX_LINES_TOTAL = 5000,     -- Show warning if larger than this
  DEFER_MS = 50,              -- Delay for deferred rendering
}

---@class file_history.DiffLine
---@field type "add"|"delete"|"context"|"header"|"no_newline"|"file_header"|"side_by_side"
---@field text string
---@field line_num? number  -- original line number if applicable
---@field left_text? string -- for side_by_side: left column text
---@field right_text? string -- for side_by_side: right column text

---@class file_history.DiffStats
---@field hunks number
---@field added number
---@field deleted number

---Parse hunk header to extract stats
---@param header string
---@return {old_start:number, old_count:number, new_start:number, new_count:number}?
local function parse_hunk_header(header)
  -- Format: @@ -old_start,old_count +new_start,new_count @@
  local old_start, old_count, new_start, new_count = header:match("@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
  if not old_start then
    return nil
  end
  return {
    old_start = tonumber(old_start) or 0,
    old_count = tonumber(old_count) or 1,
    new_start = tonumber(new_start) or 0,
    new_count = tonumber(new_count) or 1,
  }
end

---Strip the leading diff character (+, -, or space) from a line
---@param line string
---@return string
local function strip_diff_prefix(line)
  if #line > 0 then
    return line:sub(2)
  end
  return line
end

---Parse a unified diff and classify each line
---@param diff_text string
---@return file_history.DiffLine[], file_history.DiffStats
function M.parse_diff(diff_text)
  local lines = vim.split(diff_text, "\n", { plain = true, trimempty = true })
  local result = {}
  local stats = { hunks = 0, added = 0, deleted = 0 }
  local no_newline_markers = {} -- Collect these to move to end

  for i, line in ipairs(lines) do
    local diff_line = { text = line }

    -- Handle "No newline at end of file" marker - collect for later
    if line:match("^\\ No newline at end of file") then
      diff_line.type = "no_newline"
      table.insert(no_newline_markers, diff_line)
    -- Git patch headers and metadata
    elseif line:match("^diff ")
        or line:match("^index ")
        or line:match("^%-%-%-")
        or line:match("^%+%+%+") then
      diff_line.type = "header"
      table.insert(result, diff_line)
    -- Hunk headers
    elseif line:match("^@@") then
      diff_line.type = "header"
      stats.hunks = stats.hunks + 1
      local hunk_info = parse_hunk_header(line)
      if hunk_info then
        diff_line.hunk_info = hunk_info
      end
      table.insert(result, diff_line)
    -- Added lines - strip the leading +
    elseif line:match("^%+") and not line:match("^%+%+%+") then
      diff_line.type = "add"
      diff_line.text = strip_diff_prefix(line)
      stats.added = stats.added + 1
      table.insert(result, diff_line)
    -- Deleted lines - strip the leading -
    elseif line:match("^%-") and not line:match("^%-%-%- ") then
      diff_line.type = "delete"
      diff_line.text = strip_diff_prefix(line)
      stats.deleted = stats.deleted + 1
      table.insert(result, diff_line)
    -- Context lines (unchanged) - strip the leading space
    elseif line:match("^ ") then
      diff_line.type = "context"
      diff_line.text = strip_diff_prefix(line)
      table.insert(result, diff_line)
    -- Other lines (empty lines, etc.)
    else
      diff_line.type = "context"
      table.insert(result, diff_line)
    end
  end

  -- Add all "No newline" markers at the end of the result
  for _, marker in ipairs(no_newline_markers) do
    table.insert(result, marker)
  end

  return result, stats
end

---Format header lines based on user preference
---@param parsed_lines file_history.DiffLine[]
---@param stats file_history.DiffStats
---@return file_history.DiffLine[]
local function format_headers(parsed_lines, stats)
  local header_style = M.opts.header_style or "text"

  if header_style == "none" then
    -- Remove all header lines
    local filtered = {}
    for _, line in ipairs(parsed_lines) do
      if line.type ~= "header" then
        table.insert(filtered, line)
      end
    end
    return filtered
  elseif header_style == "text" then
    -- Replace headers with human-readable text
    local result = {}
    local i = 1
    while i <= #parsed_lines do
      local line = parsed_lines[i]

      -- Skip file headers (diff, index, ---, +++)
      if line.type == "header" and not line.text:match("^@@") then
        -- Skip this header line
        i = i + 1
      -- Convert hunk headers to readable format
      elseif line.type == "header" and line.text:match("^@@") then
        -- Add a summary line instead
        local summary = {}
        if stats.added > 0 then
          table.insert(summary, string.format("+%d", stats.added))
        end
        if stats.deleted > 0 then
          table.insert(summary, string.format("-%d", stats.deleted))
        end
        if stats.hunks > 0 then
          table.insert(summary, string.format("~%d hunks", stats.hunks))
        end

        if #summary > 0 then
          table.insert(result, {
            type = "header",
            text = "Changes: " .. table.concat(summary, ", "),
          })
        end
        i = i + 1
      else
        table.insert(result, line)
        i = i + 1
      end
    end
    return result
  else
    -- "raw" - keep headers as-is
    return parsed_lines
  end
end

---Filter "No newline at end of file" markers based on user preference
---@param parsed_lines file_history.DiffLine[]
---@return file_history.DiffLine[]
local function filter_no_newline(parsed_lines)
  if M.opts.show_no_newline then
    return parsed_lines
  end

  -- Remove all "no_newline" markers
  local filtered = {}
  for _, line in ipairs(parsed_lines) do
    if line.type ~= "no_newline" then
      table.insert(filtered, line)
    end
  end
  return filtered
end

---Convert inline diff to side-by-side format
---@param parsed_lines file_history.DiffLine[]
---@param win_width number
---@return file_history.DiffLine[]
local function convert_to_side_by_side(parsed_lines, win_width)
  local result = {}
  local col_width = math.floor((win_width - 3) / 2) -- -3 for separator " │ "
  local separator = " │ "

  local i = 1
  while i <= #parsed_lines do
    local line = parsed_lines[i]

    if line.type == "header" or line.type == "file_header" or line.type == "no_newline" then
      -- Headers span full width
      table.insert(result, line)
      i = i + 1
    elseif line.type == "context" then
      -- Context: same on both sides
      local text = line.text or ""
      local left = text:sub(1, col_width)
      local right = text:sub(1, col_width)
      -- Pad to column width
      left = left .. string.rep(" ", col_width - vim.fn.strdisplaywidth(left))
      right = right .. string.rep(" ", col_width - vim.fn.strdisplaywidth(right))
      table.insert(result, {
        type = "side_by_side",
        text = left .. separator .. right,
        left_type = "context",
        right_type = "context",
      })
      i = i + 1
    elseif line.type == "delete" then
      -- Look ahead for matching add
      local left_text = (line.text or ""):sub(1, col_width)
      left_text = left_text .. string.rep(" ", col_width - vim.fn.strdisplaywidth(left_text))
      
      local right_text = ""
      local right_type = "empty"
      
      -- Check if next line is an add (paired change)
      if i + 1 <= #parsed_lines and parsed_lines[i + 1].type == "add" then
        right_text = (parsed_lines[i + 1].text or ""):sub(1, col_width)
        right_type = "add"
        i = i + 1 -- skip the add line since we're pairing it
      end
      right_text = right_text .. string.rep(" ", col_width - vim.fn.strdisplaywidth(right_text))
      
      table.insert(result, {
        type = "side_by_side",
        text = left_text .. separator .. right_text,
        left_type = "delete",
        right_type = right_type,
        col_width = col_width,
        separator_pos = col_width,
      })
      i = i + 1
    elseif line.type == "add" then
      -- Add without preceding delete
      local left_text = string.rep(" ", col_width)
      local right_text = (line.text or ""):sub(1, col_width)
      right_text = right_text .. string.rep(" ", col_width - vim.fn.strdisplaywidth(right_text))
      
      table.insert(result, {
        type = "side_by_side",
        text = left_text .. separator .. right_text,
        left_type = "empty",
        right_type = "add",
        col_width = col_width,
        separator_pos = col_width,
      })
      i = i + 1
    else
      table.insert(result, line)
      i = i + 1
    end
  end

  return result
end

---Apply syntax highlighting to a diff buffer
---@param buf number
---@param parsed_lines file_history.DiffLine[]
---@param win? number Window handle for getting width (optional)
function M.highlight_diff(buf, parsed_lines, win)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  local highlight_style = M.opts.highlight_style or "full"
  local win_width = nil

  -- Get window width if we need full-width highlights
  if highlight_style == "full" and win and vim.api.nvim_win_is_valid(win) then
    win_width = vim.api.nvim_win_get_width(win)
  end

  for i, diff_line in ipairs(parsed_lines) do
    local line_idx = i - 1  -- 0-indexed for nvim API
    local hl_group = nil

    -- Handle side-by-side lines with split highlighting
    if diff_line.type == "side_by_side" then
      local col_width = diff_line.col_width or 40
      local sep_pos = diff_line.separator_pos or col_width
      
      -- Highlight left side
      if diff_line.left_type == "delete" then
        vim.api.nvim_buf_add_highlight(buf, ns, "DiffDelete", line_idx, 0, sep_pos)
      elseif diff_line.left_type == "context" then
        -- No highlight for context (default text color)
      end
      
      -- Highlight right side (after separator)
      local right_start = sep_pos + 3 -- " │ " is 3 chars wide visually but may be more bytes
      if diff_line.right_type == "add" then
        vim.api.nvim_buf_add_highlight(buf, ns, "DiffAdd", line_idx, right_start, -1)
      elseif diff_line.right_type == "context" then
        -- No highlight for context
      end
    else
      -- Regular inline diff highlighting
      if diff_line.type == "add" then
        hl_group = "DiffAdd"
      elseif diff_line.type == "delete" then
        hl_group = "DiffDelete"
      elseif diff_line.type == "header" then
        hl_group = "DiffChange"
      elseif diff_line.type == "no_newline" then
        hl_group = "FileHistoryNoNewline"
      elseif diff_line.type == "file_header" then
        hl_group = "DiffChange"  -- Use DiffChange for file header background
      end
      -- Note: "context" lines get no highlight (default text color)

      if hl_group then
        if highlight_style == "full" and win_width then
          -- Full-width highlight using virtual text overlay
          -- First highlight the actual text
          vim.api.nvim_buf_add_highlight(buf, ns, hl_group, line_idx, 0, -1)

          -- For file_header with icon, apply icon highlight separately to preserve fg color
          if diff_line.type == "file_header" and diff_line.icon_hl and diff_line.icon_end then
            -- Get the background color from the header highlight group
            local header_bg = vim.api.nvim_get_hl(0, { name = hl_group })

            -- Create a combined highlight for the icon with its fg and header bg
            local combined_hl = "FileHistoryIcon_" .. (diff_line.icon_hl or "Default")
            local icon_fg = vim.api.nvim_get_hl(0, { name = diff_line.icon_hl or "Normal" })
            vim.api.nvim_set_hl(0, combined_hl, {
              fg = icon_fg.fg,
              bg = header_bg.bg,
            })

            -- Apply the combined highlight to just the icon
            vim.api.nvim_buf_add_highlight(buf, ns, combined_hl, line_idx, 2, diff_line.icon_end)
          end

          -- Then extend to fill the line with overlay (snacks.nvim approach)
          local line_text = vim.api.nvim_buf_get_lines(buf, line_idx, line_idx + 1, false)[1] or ""
          vim.api.nvim_buf_set_extmark(buf, ns, line_idx, #line_text, {
            virt_text = { { string.rep(" ", 1000), hl_group } },
            virt_text_pos = "overlay",
            hl_mode = "replace",
          })
        else
          -- Text-only highlight (just the actual characters)
          vim.api.nvim_buf_add_highlight(buf, ns, hl_group, line_idx, 0, -1)

          -- For file_header with icon, apply icon highlight separately
          if diff_line.type == "file_header" and diff_line.icon_hl and diff_line.icon_end then
            vim.api.nvim_buf_add_highlight(buf, ns, diff_line.icon_hl, line_idx, 2, diff_line.icon_end)
          end
        end
      end
    end
  end
end

---Create file header block similar to snacks.nvim git_diff
---@param filepath string The filepath to display
---@return file_history.DiffLine[] Header lines
---Create file header block similar to snacks.nvim git_diff
---@param filepath string The filepath to display
---@param win_width? number Optional window width for wrapping
---@return file_history.DiffLine[] Header lines
---Create file header block similar to snacks.nvim git_diff
---@param filepath string The filepath to display
---@param win_width? number Optional window width (unused, wrapping handled by Neovim)
---@return file_history.DiffLine[] Header lines
local function create_file_header(filepath, win_width)
  local header = {}

  -- Get icon for the file
  local filename = vim.fn.fnamemodify(filepath, ":t")
  local icon, icon_hl = Snacks.util.icon(filename, "file")

  -- Build the content line: "  icon  filepath"
  local content = "  " .. icon .. "  " .. filepath
  local icon_end_pos = 2 + vim.fn.strdisplaywidth(icon)

  -- Line 1: Empty line with header background (top padding)
  table.insert(header, {
    type = "file_header",
    text = "",
  })

  -- Line 2: Icon + filepath (Neovim handles wrapping via window wrap option)
  table.insert(header, {
    type = "file_header",
    text = content,
    icon_hl = icon_hl,
    icon_end = icon_end_pos,
  })

  -- Line 3: Empty line with header background (bottom padding)
  table.insert(header, {
    type = "file_header",
    text = "",
  })

  return header
end



---Render diff with appropriate performance handling
---@param ctx table Snacks picker preview context
---@param diff_text string The unified diff string
---@param filepath? string Optional filepath to display in header
function M.render_diff(ctx, diff_text, filepath)
  local preview = ctx.preview

  -- Parse the diff
  local parsed, stats = M.parse_diff(diff_text)

  -- Format headers based on user preference
  parsed = format_headers(parsed, stats)

  -- Filter "No newline at end of file" markers based on user preference
  parsed = filter_no_newline(parsed)

  -- Prepend file header if filepath is provided
  if filepath then
    local header_lines = create_file_header(filepath, win_width)
    -- Insert header lines at the beginning
    for i = #header_lines, 1, -1 do
      table.insert(parsed, 1, header_lines[i])
    end
  end

  -- Convert to side-by-side if requested
  local win = ctx.win
  if M.opts.diff_style == "side_by_side" and win and vim.api.nvim_win_is_valid(win) then
    local win_width = vim.api.nvim_win_get_width(win)
    parsed = convert_to_side_by_side(parsed, win_width)
  end

  local line_count = #parsed

  -- Handle very large diffs
  if line_count > PERF.MAX_LINES_TOTAL then
    preview:notify(
      string.format("Large diff (%d lines). Showing first %d lines.",
        line_count, PERF.MAX_LINES_TOTAL),
      "warn"
    )
    -- Truncate to max lines
    local truncated = {}
    for i = 1, PERF.MAX_LINES_TOTAL do
      table.insert(truncated, parsed[i])
    end
    parsed = truncated
  end

  -- Extract text for buffer
  local text_lines = {}
  for _, diff_line in ipairs(parsed) do
    table.insert(text_lines, diff_line.text)
  end

  -- Reset preview and set content
  preview:reset()
  preview:set_lines(text_lines)

  -- Apply highlighting based on size
  if line_count <= PERF.MAX_LINES_INSTANT then
    -- Small diff: highlight immediately
    M.highlight_diff(ctx.buf, parsed, win)
  elseif line_count <= PERF.MAX_LINES_DEFERRED then
    -- Medium diff: defer highlighting slightly
    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(ctx.buf) then
        M.highlight_diff(ctx.buf, parsed, win)
      end
    end, PERF.DEFER_MS)
  else
    -- Large diff: highlight in chunks to avoid blocking
    local chunk_size = 200
    local current_idx = 1

    -- Get highlight style once for chunked rendering
    local highlight_style = M.opts.highlight_style or "full"

    local function highlight_chunk()
      if not vim.api.nvim_buf_is_valid(ctx.buf) then
        return
      end

      local end_idx = math.min(current_idx + chunk_size - 1, #parsed)

      for i = current_idx, end_idx do
        local diff_line = parsed[i]
        local line_idx = i - 1
        local hl_group = nil

        if diff_line.type == "add" then
          hl_group = "DiffAdd"
        elseif diff_line.type == "delete" then
          hl_group = "DiffDelete"
        elseif diff_line.type == "header" then
          hl_group = "DiffChange"
        elseif diff_line.type == "no_newline" then
          hl_group = "FileHistoryNoNewline"
        elseif diff_line.type == "file_header" then
          hl_group = "DiffChange"  -- Use DiffChange for file header background
        end

        if hl_group then
          if highlight_style == "full" and win then
            -- Full-width highlight
            vim.api.nvim_buf_add_highlight(ctx.buf, ns, hl_group, line_idx, 0, -1)

            -- For file_header with icon, apply icon highlight separately to preserve fg color
            if diff_line.type == "file_header" and diff_line.icon_hl and diff_line.icon_end then
              -- Get the background color from the header highlight group
              local header_bg = vim.api.nvim_get_hl(0, { name = hl_group })

              -- Create a combined highlight for the icon with its fg and header bg
              local combined_hl = "FileHistoryIcon_" .. (diff_line.icon_hl or "Default")
              local icon_fg = vim.api.nvim_get_hl(0, { name = diff_line.icon_hl or "Normal" })
              vim.api.nvim_set_hl(0, combined_hl, {
                fg = icon_fg.fg,
                bg = header_bg.bg,
              })

              -- Apply the combined highlight to just the icon
              vim.api.nvim_buf_add_highlight(ctx.buf, ns, combined_hl, line_idx, 2, diff_line.icon_end)
            end

            local line_text = vim.api.nvim_buf_get_lines(ctx.buf, line_idx, line_idx + 1, false)[1] or ""
            vim.api.nvim_buf_set_extmark(ctx.buf, ns, line_idx, #line_text, {
              virt_text = { { string.rep(" ", 1000), hl_group } },
              virt_text_pos = "overlay",
              hl_mode = "replace",
            })
          else
            -- Text-only highlight
            vim.api.nvim_buf_add_highlight(ctx.buf, ns, hl_group, line_idx, 0, -1)

            -- For file_header with icon, apply icon highlight separately
            if diff_line.type == "file_header" and diff_line.icon_hl and diff_line.icon_end then
              vim.api.nvim_buf_add_highlight(ctx.buf, ns, diff_line.icon_hl, line_idx, 2, diff_line.icon_end)
            end
          end
        end
      end

      current_idx = end_idx + 1

      if current_idx <= #parsed then
        vim.defer_fn(highlight_chunk, 10)
      end
    end

    highlight_chunk()
  end

  -- Set buffer options for better diff viewing
  if vim.api.nvim_buf_is_valid(ctx.buf) then
    vim.bo[ctx.buf].filetype = "diff"
    vim.bo[ctx.buf].modifiable = false
  end

  -- Set window options
  if win and vim.api.nvim_win_is_valid(win) then
    vim.wo[win].wrap = M.opts.wrap
  end
end

---Enhanced diff stats for picker items (optional)
---@param diff_text string
---@return {added: number, deleted: number, changed: number}
function M.get_diff_stats(diff_text)
  local _, stats = M.parse_diff(diff_text)
  return {
    added = stats.added,
    deleted = stats.deleted,
    changed = stats.hunks,
  }
end

---Setup function to configure preview options
---@param opts? {header_style?: "text"|"raw"|"none", diff_style?: "inline"|"side_by_side"}
function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
end

return M
