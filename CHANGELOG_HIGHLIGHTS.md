# Diff Highlighting Update - Summary

## What's New

### 🐛 Bug Fixes

1. **"No newline at end of file" marker** now properly handled
   - Previously inserted incorrectly within diff content
   - Now highlighted with custom `FileHistoryNoNewline` highlight group
   - Always appears at the end of the diff (never between add/remove lines)
   - Can be hidden completely via `show_no_newline = false` option
   - Clearly distinguished from actual file content

### ✨ New Features

1. **Configurable Header Display** - Three modes:
   - **"text"** (default): Clean, JetBrains-style summary
     ```
     Changes: +15, -8, ~3 hunks
     ```
   - **"raw"**: Full git patch headers
     ```
     diff --git a/file.lua b/file.lua
     @@ -10,7 +10,7 @@
     ```
   - **"none"**: No headers at all (cleanest view)

2. **Full-Width Highlight Style** - Two modes:
   - **"full"** (default): Extends highlights to the full window width
     - Looks like IDE diff views (VS Code, JetBrains, etc.)
     - Uses virtual text overlay (snacks.nvim approach)
     - Prevents line wrapping with large virtual text
   - **"text"**: Only highlights actual text characters
     - Minimal highlighting, stops where text ends

3. **Line Wrapping Control**:
   - **wrap = false** (default): Lines extend beyond window, use horizontal scrolling
     - Recommended with `highlight_style = "full"`
     - Prevents visual artifacts from wrapped highlights
   - **wrap = true**: Long lines wrap within window
     - Better readability but may break diff alignment

4. **Enhanced Diff Statistics**
   - Automatic counting of additions, deletions, and hunks
   - Used in "text" header mode for summary

5. **"No newline at end of file" Control**:
   - **show_no_newline = true** (default): Display markers with custom highlight
   - **show_no_newline = false**: Hide markers completely
   - Uses `FileHistoryNoNewline` highlight group (linked to `NonText`)
   - Can be customized to match your colorscheme

### 🎨 Visual Improvements

- Proper syntax highlighting for all diff elements
- "No newline at end of file" markers use dedicated highlight group
- Headers formatted based on user preference
- Full-width or text-only highlighting based on preference
- Consistent with Neovim's standard diff highlight groups

## Configuration

```lua
require("file_history").setup({
  preview = {
    header_style = "text", -- "text", "raw", or "none"
    highlight_style = "full", -- "full" or "text"
    wrap = false, -- whether to wrap lines in preview window
    show_no_newline = true, -- whether to show "\ No newline at end of file" markers
  },
})
```

## Defaults

- Header style: `"text"` (clean, human-readable)
- Highlight style: `"full"` (extends to window width)
- Line wrapping: `false` (no wrap, use horizontal scrolling)
- Show "No newline" markers: `true` (display with special highlight)
- Performance thresholds: Optimized for smooth scrolling
- Highlight groups: Uses standard Neovim diff colors

## Migration

No breaking changes! The plugin works exactly as before, but with:
- Better visual clarity
- Fixed bugs
- Optional configuration for power users

## Examples

### Text Mode (Default)
```
Changes: +15, -8, ~3 hunks
 function example() {
-  return old_value
+  return new_value
 }
\ No newline at end of file
```

### Raw Mode
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
\ No newline at end of file
```

### None Mode
```
 function example() {
-  return old_value
+  return new_value
 }
\ No newline at end of file
```

## Performance

All optimizations from the original implementation remain:
- ✅ Instant rendering for small diffs (0-500 lines)
- ✅ Deferred rendering for medium diffs (501-2000 lines)
- ✅ Chunked rendering for large diffs (2001-5000 lines)
- ✅ Warning + truncation for very large diffs (5000+ lines)

No performance regression - the header formatting adds negligible overhead.
