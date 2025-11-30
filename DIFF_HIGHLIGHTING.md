# Diff Highlighting Improvements

This document describes the enhanced diff preview functionality added to file-history.nvim.

## Overview

The plugin now provides proper syntax highlighting for diff previews in the picker, making it much easier to see what has changed between file snapshots.

## Features

### 1. **Proper Diff Highlighting**

- **Added lines** (`+`): Highlighted with `DiffAdd` highlight group (typically green)
- **Deleted lines** (`-`): Highlighted with `DiffDelete` highlight group (typically red)
- **Modified hunks** (`@@`): Highlighted with `DiffChange` highlight group (typically yellow/orange)
- **Context lines**: No special highlighting (normal text color)
- **"No newline at end of file"** markers: Highlighted with `Comment` group (dimmed)

### 2. **Configurable Header Display**

You can now control how diff headers are displayed with three different modes:

#### **"text"** (default) - Human-Readable Summary

Shows a clean summary line instead of raw git patch headers:

```
Changes: +15, -8, ~3 hunks
 function example() {
-  return old_value
+  return new_value
 }
```

Benefits:
- Clean, JetBrains-style interface
- Quick overview of changes at a glance
- No visual clutter from git metadata

#### **"raw"** - Full Git Patch Headers

Shows the complete git diff format with all metadata:

```
diff --git a/file.lua b/file.lua
index abc123..def456 100644
--- a/file.lua
+++ b/file.lua
@@ -10,7 +10,7 @@ function example()
 function example() {
-  return old_value
+  return new_value
 }
```

Benefits:
- Full context for power users
- Useful for understanding exact changes
- Compatible with git patch tools

#### **"none"** - Headers Completely Hidden

Shows only the actual code changes:

```
 function example() {
-  return old_value
+  return new_value
 }
```

Benefits:
- Maximum focus on code changes
- Cleanest possible view
- Perfect for quick reviews

### 3. **Git Patch Format Support**

The implementation correctly handles all aspects of unified diff format:

- Diff headers (`diff --git`, `index`, `---`, `+++`)
- Hunk headers (`@@ -start,count +start,count @@`)
- Added/deleted/context lines with proper prefix detection
- **"No newline at end of file"** markers (properly handled and dimmed)
- Handles edge cases like `---` file markers vs deleted lines

### 4. **Performance Optimizations**

The preview rendering includes intelligent performance handling:

#### Thresholds

- **0-500 lines**: Instant highlighting (no delay)
- **501-2000 lines**: Deferred highlighting with 50ms delay
- **2001-5000 lines**: Chunked highlighting (200 lines at a time, 10ms between chunks)
- **5000+ lines**: Shows warning and truncates to first 5000 lines

#### Benefits

- **No lag** when scrolling through small/medium diffs
- **Smooth navigation** even with larger diffs
- **Prevents Neovim freezing** on very large changes
- **Progressive rendering** keeps UI responsive

### 4. **Diff Statistics** (Optional)

The preview module also provides a utility function to extract diff stats:

```lua
local stats = require("file_history.preview").get_diff_stats(diff_text)
-- Returns: { added = 10, deleted = 5, changed = 2 }
```

This can be used to enhance the picker item display with change counts.

## Implementation Details

### Architecture

The implementation consists of two main components:

1. **`lua/file_history/preview.lua`**: New module containing:
   - `parse_diff()`: Parses unified diff format
   - `highlight_diff()`: Applies syntax highlighting
   - `render_diff()`: Main rendering function with performance handling
   - `get_diff_stats()`: Utility for extracting statistics

2. **Modified `lua/file_history/init.lua`**: Updated preview functions to use the new module

### How It Works

1. **Parsing**: Each line of the diff is classified by its prefix:
   - `+` (not `+++`) → added line
   - `-` (not `---`) → deleted line
   - `@@` or diff metadata → header
   - Everything else → context

2. **Highlighting**: Uses `vim.api.nvim_buf_add_highlight()` to apply highlight groups to the entire line

3. **Performance**: Based on line count, chooses one of three rendering strategies:
   - Immediate (small)
   - Deferred (medium)
   - Chunked (large)

### Highlight Groups Used

The implementation uses Neovim's standard diff highlight groups:

- `DiffAdd`: For added lines
- `DiffDelete`: For deleted lines
- `DiffChange`: For headers and modified sections

These respect your colorscheme and any custom highlight overrides.

## Configuration

### Basic Setup

In your plugin configuration:

```lua
require("file_history").setup({
  preview = {
    header_style = "text", -- "text", "raw", or "none"
    highlight_style = "full", -- "full" or "text"
    wrap = false, -- whether to wrap lines in preview window
  },
})
```

### Header Style Options

Choose the header display style that fits your workflow:

```lua
-- Default: Clean summary (JetBrains-style)
preview = {
  header_style = "text"
}

-- Power user: Full git patch format
preview = {
  header_style = "raw"
}

-- Minimalist: No headers at all
preview = {
  header_style = "none"
}
```

### Highlight Style Options

Control how diff highlights are rendered:

```lua
-- Default: Full-width highlighting (extends to window edge)
preview = {
  highlight_style = "full"
}

-- Minimal: Only highlight actual text characters
preview = {
  highlight_style = "text"
}
```

**"full"** (default): Extends the highlight color to the full width of the preview window, similar to how IDEs display diffs. Uses virtual text to pad the line to the window edge.

**"text"**: Only highlights the actual text characters on each line. The highlight stops where the text ends.

### Line Wrapping

Control whether long lines wrap in the preview window:

```lua
-- Default: No wrapping (lines extend beyond window)
preview = {
  wrap = false
}

-- Enable wrapping for long lines
preview = {
  wrap = true
}
```

**false** (default): Long lines extend beyond the window edge. Use horizontal scrolling to view. This is recommended when using `highlight_style = "full"` to prevent visual artifacts.

**true**: Long lines wrap to fit within the window. Better for readability but may break the visual alignment of diffs.

## Usage

The improvements are automatic - no extra commands needed. Just use the plugin as before:

```vim
:FileHistory history
```

When you navigate between snapshots in the picker, the diff preview will now show:
- ✅ Green highlighting for additions
- ❌ Red highlighting for deletions
- 📝 Yellow/orange highlighting for headers (if visible)
- 💬 Dimmed "No newline at end of file" markers
- ⚡ Optimized rendering for all file sizes
- 🎨 Customizable header display

## Customization

### Adjust Performance Thresholds

You can modify the thresholds in `lua/file_history/preview.lua`:

```lua
local PERF = {
  MAX_LINES_INSTANT = 500,    -- Render instantly if diff is smaller
  MAX_LINES_DEFERRED = 2000,  -- Defer rendering if between 500-2000
  MAX_LINES_TOTAL = 5000,     -- Show warning if larger than this
  DEFER_MS = 50,              -- Delay for deferred rendering
}
```

### Custom Highlight Groups

You can override the highlight groups in your config:

```lua
vim.api.nvim_set_hl(0, 'DiffAdd', { bg = '#2d4d2d', fg = '#a0f0a0' })
vim.api.nvim_set_hl(0, 'DiffDelete', { bg = '#4d2d2d', fg = '#f0a0a0' })
vim.api.nvim_set_hl(0, 'DiffChange', { bg = '#4d4d2d', fg = '#f0f0a0' })
vim.api.nvim_set_hl(0, 'Comment', { fg = '#808080', italic = true })
```

## Bug Fixes

### "No newline at end of file" Issue

**Fixed**: The "\ No newline at end of file" marker is now properly recognized and:
- Highlighted with the `Comment` group (dimmed)
- No longer inserted incorrectly within diff content
- Treated as special metadata rather than code

Example before fix:
```diff
-return {}
\ No newline at end of file
+return {}
```

Example after fix:
```diff
-return {}
+return {}
\ No newline at end of file  (dimmed)
```

## Technical Notes

### Why Not Use `snacks_picker.preview.diff()`?

While snacks.nvim provides a `preview.diff()` function, it expects specific data structures and includes features (like annotations, complex formatting) that aren't needed for basic file history diffs. The custom implementation:

- Is simpler and more focused
- Has better performance control for this specific use case
- Provides exactly the highlighting needed without extra overhead
- Maintains full compatibility with the existing plugin architecture

### Memory Efficiency

The implementation is memory efficient:
- Parses diffs on-demand (not stored)
- Uses Neovim's built-in highlight namespace system
- Clears highlights when switching between items
- Doesn't keep large diff strings in memory unnecessarily

## Future Enhancements

Potential improvements that could be added:

1. **Inline diff stats** in picker items (e.g., `+10 -5`)
2. **Word-level diff highlighting** for modified lines
3. **Configurable colorscheme-aware highlights**
4. **Side-by-side diff view** option
5. **Fold support** for large unchanged sections

## Troubleshooting

### Highlights not showing

1. Check if `DiffAdd`, `DiffDelete`, `DiffChange` are defined:
   ```vim
   :highlight DiffAdd
   :highlight DiffDelete
   :highlight DiffChange
   ```

2. Try clearing highlights manually:
   ```vim
   :lua vim.api.nvim_buf_clear_namespace(0, -1, 0, -1)
   ```

### Performance issues

If you experience lag with very large diffs:
- Lower the `MAX_LINES_TOTAL` threshold
- Increase `DEFER_MS` delay
- Reduce `chunk_size` for chunked rendering

### Incorrect highlighting

If some lines are highlighted incorrectly:
- Check the diff format - the parser expects standard unified diff format
- Verify the diff is generated correctly by vim.diff() or git
- Look for unusual line prefixes that might confuse the parser
