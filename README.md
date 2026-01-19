# file-history.nvim

![Lua](https://img.shields.io/badge/Made%20with%20Lua-blueviolet.svg?style=for-the-badge&logo=lua)

A Neovim plugin that provides comprehensive file history tracking and diff visualization using [snacks.nvim](https://github.com/folke/snacks.nvim) picker. Think of it as local version control with a beautiful, IDE-like interface for every file you edit.

## Features

- 📸 **Automatic Snapshots**: Every file save creates a timestamped snapshot in a git repository
- 🔍 **Beautiful Diff Viewer**: Syntax-highlighted diffs with full-width highlighting (similar to VS Code, JetBrains IDEs)
- 🏷️ **Tagged Backups**: Manually create tagged snapshots for important checkpoints
- 📁 **Multi-File Support**: Browse and compare snapshots across all tracked files
- 🕐 **Time-Based Queries**: Find snapshots within specific date ranges
- ⚡ **Performance Optimized**: Intelligent rendering with deferred highlighting for large diffs
- 🎨 **Highly Customizable**: Configure header styles, highlight modes, line wrapping, and more
- 🔄 **Revert Support**: Easily restore files to previous versions

## Requirements

- Neovim >= 0.9.0
- [folke/snacks.nvim](https://github.com/folke/snacks.nvim)
- Git

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "file-history.nvim",
  dependencies = { "folke/snacks.nvim" },
  opts = {
    -- Configuration options (see below)
  },
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "file-history.nvim",
  requires = { "folke/snacks.nvim" },
  config = function()
    require("file_history").setup({
      -- Configuration options
    })
  end
}
```

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `:FileHistory history` | Show snapshot history for the current file |
| `:FileHistory history_range` | Show history for visually selected lines |
| `:FileHistory files` | Browse all tracked files |
| `:FileHistory backup` | Create a tagged snapshot of the current file |
| `:FileHistory query` | Search snapshots by date range |

### Visual Range History

Select lines in visual mode and view history for just that section:

1. Enter visual mode and select lines (`V` or `v`)
2. Run `:'<,'>FileHistory history_range`

The picker will show only history items where changes affected the selected lines, and the preview will highlight only the relevant hunks.

**Suggested Mapping:**
```lua
vim.keymap.set("v", "<leader>fh", function()
  vim.cmd("'<,'>FileHistory history_range")
end, { desc = "File history for selection" })
```

### Default Key Bindings (in picker)

| Key | Action | Mode |
|-----|--------|------|
| `<CR>` | Revert current buffer to selected snapshot | Normal |
| `<M-o>` | Open selected snapshot in new tab | Normal/Insert |
| `<M-d>` | Open diff in new tab | Normal/Insert |
| `<M-a>` | Yank all additions from diff | Normal/Insert |
| `<M-x>` | Yank all deletions from diff | Normal/Insert |
| `<M-l>` | Toggle incremental diff mode | Normal/Insert |
| `<M-p>` | Purge file history (files picker) | Normal/Insert |

## Configuration

### Full Configuration Example

```lua
require("file_history").setup({
  -- Git repository location for storing snapshots
  backup_dir = "~/.file-history-git",

  -- Git command to use
  git_cmd = "git",

  -- Enable debug logging (for troubleshooting)
  debug = false,

  -- Diff generation options passed to vim.diff()
  -- See :help vim.diff() for all available options
  diff_opts = {
    result_type = "unified",        -- Required for preview rendering
    ctxlen = 3,                     -- Context lines around changes
    algorithm = "histogram",        -- Better for real-world diffs with scattered changes
    linematch = 60,                 -- Align lines within hunks (higher = more aggressive)
  },

  -- Preview window options
  preview = {
    -- Header display style: "text", "raw", or "none"
    -- "text" (default): Clean summary like "Changes: +10, -5, ~2 hunks"
    -- "raw": Full git patch headers
    -- "none": No headers at all
    header_style = "text",

    -- Highlight style: "full" or "text"
    -- "full" (default): Extends highlights to window width (IDE-like)
    -- "text": Only highlights actual text characters
    highlight_style = "full",

    -- Diff content line wrapping
    -- false (default): Use horizontal scrolling
    -- true: Wrap long lines
    wrap = false,

    -- Filepath header wrapping
    -- true (default): Long paths wrap to multiple lines
    -- false: Truncate long paths
    title_wrap = true,

    -- Diff display style
    -- "inline" (default): Traditional unified diff
    -- "side_by_side": Two-column comparison
    diff_style = "inline",

    -- Show "\ No newline at end of file" markers
    -- true (default): Display with custom highlight
    -- false: Hide completely
    show_no_newline = true,
  },

  -- Customize key bindings
  key_bindings = {
    open_buffer_diff_tab = "<M-d>",
    open_file_diff_tab = "<M-d>",
    open_snapshot_tab = "<M-o>",
    toggle_incremental = "<M-l>",
    yank_additions = "<M-a>",
    yank_deletions = "<M-x>",
    delete_history = "<M-d>",
    purge_history = "<M-p>",
  },
})
```

### Minimal Configuration

```lua
require("file_history").setup({
  -- Just specify where to store snapshots
  backup_dir = "~/.file-history-git",
})
```

## Preview Customization

### Header Styles

#### "text" (Default) - Clean Summary
```
Changes: +15, -8, ~3 hunks
+added line
-removed line
 context line
```

#### "raw" - Full Git Headers
```
diff --git a/file.lua b/file.lua
index abc123..def456 100644
--- a/file.lua
+++ b/file.lua
@@ -10,7 +10,7 @@ function example()
+added line
-removed line
```

#### "none" - No Headers
```
+added line
-removed line
 context line
```

### Highlight Styles

#### "full" (Default) - IDE-like Full-Width
Highlights extend to the full window width, matching VS Code, JetBrains, and other modern IDEs.

#### "text" - Minimal
Only highlights the actual text characters, stops where text ends.

### File Header Display

Every diff preview includes a file header showing:
```
[padding line]
  📄  /absolute/path/to/your/file.lua
[padding line]
```

The icon color is preserved while the background matches the diff header style.

## Highlight Groups

### Default Highlight Groups

| Group | Purpose | Default Link |
|-------|---------|--------------|
| `DiffAdd` | Added lines | Built-in diff highlight |
| `DiffDelete` | Deleted lines | Built-in diff highlight |
| `DiffChange` | Headers and file header background | Built-in diff highlight |
| `FileHistoryNoNewline` | "No newline at end of file" markers | `NonText` |
| `FileHistoryTime` | Timestamp in list | `Number` |
| `FileHistoryDate` | Date in list | `Function` |
| `FileHistoryFile` | Filename in list | `Keyword` |
| `FileHistoryTag` | Tag name in list | `Comment` |

### Customizing Highlights

```lua
-- Override the "No newline" marker appearance
vim.api.nvim_set_hl(0, "FileHistoryNoNewline", {
  fg = "#666666",
  italic = true
})

-- Customize diff colors
vim.api.nvim_set_hl(0, "DiffAdd", {
  bg = "#2d4d2d",
  fg = "#a0f0a0"
})
```

## Performance

The plugin includes intelligent performance optimizations:

| Diff Size | Rendering Strategy | Behavior |
|-----------|-------------------|----------|
| 0-500 lines | Instant | Highlight immediately |
| 501-2000 lines | Deferred (50ms) | Slight delay to keep UI responsive |
| 2001-5000 lines | Chunked (200 lines/10ms) | Progressive rendering |
| 5000+ lines | Truncated | Shows warning and first 5000 lines |

These thresholds can be adjusted in `lua/file_history/preview.lua` if needed.

## Workflow Examples

### Daily Development

1. Edit your file normally - snapshots are created automatically on save
2. Press `:FileHistory history` to see all versions
3. Navigate through snapshots to see what changed
4. Press `<CR>` to revert to a snapshot, or `<M-o>` to view it in a new tab
5. Use `<M-d>` for a side-by-side diff view
6. Use `<M-a>` to yank all additions or `<M-x>` to yank all deletions from the diff

### Creating Checkpoints

Before making major changes:
```vim
:FileHistory backup
" Enter a tag name like "before-refactor"
```

Later, you can easily find this checkpoint in the history.

### Finding Changes Across Files

```vim
:FileHistory files
" Browse all tracked files
" Filter with the picker's search
```

### Time-Based Queries

```vim
:FileHistory query
" After: 2024-01-01
" Before: 2024-01-31
" See all changes in January
```

## How It Works

1. **Snapshot Creation**: On every file save, the plugin:
   - Creates/updates a git repository in `backup_dir`
   - Commits the file with a timestamp and optional tag
   - Stores using the pattern: `hostname/filepath`

2. **Snapshot Retrieval**: When viewing history:
   - Uses git to retrieve all commits for the file
   - Normalizes line endings (handles Windows CRLF vs Unix LF)
   - Generates diffs using Neovim's built-in `vim.diff()` with histogram algorithm
   - Renders with syntax highlighting in snacks.nvim picker

3. **Storage**: Files are stored in a git repository, providing:
   - Efficient compression
   - Reliable versioning
   - Standard git tools for advanced operations

## Architecture

```
file-history.nvim/
├── lua/
│   └── file_history/
│       ├── init.lua           # Main plugin, picker configs
│       ├── fh.lua             # Git operations and file handling
│       ├── actions.lua        # Picker actions (revert, diff, etc.)
│       ├── preview.lua        # Diff parsing and highlighting
│       └── debug.lua          # Debug logging (when opts.debug = true)
├── plugin/
│   └── file_history.lua       # Plugin initialization
└── README.md
```

## Advanced Usage

### Custom Diff Viewer

The plugin exposes the preview module for custom usage:

```lua
local preview = require("file_history.preview")

-- Parse a diff
local parsed, stats = preview.parse_diff(diff_text)
-- stats = { added = 10, deleted = 5, hunks = 2 }

-- Get diff statistics
local stats = preview.get_diff_stats(diff_text)
```

### Programmatic Access

```lua
local fh = require("file_history.fh")

-- Get file history
local snapshots = fh.file_history()

-- Get file content at specific commit
local lines = fh.get_file(filepath, commit_hash)

-- Get commit log
local log = fh.get_log(filepath, commit_hash)
```

## Troubleshooting

### Highlights not showing

Check if diff highlight groups are defined:
```vim
:highlight DiffAdd
:highlight DiffDelete
:highlight DiffChange
```

### Performance issues with large files

Adjust the performance thresholds in `lua/file_history/preview.lua`:
```lua
local PERF = {
  MAX_LINES_INSTANT = 500,
  MAX_LINES_DEFERRED = 2000,
  MAX_LINES_TOTAL = 5000,
  DEFER_MS = 50,
}
```

### Git errors

Ensure git is installed and accessible:
```bash
which git
git --version
```

Check the backup directory has proper permissions:
```bash
ls -la ~/.file-history-git
```

### Debug Logging

If diffs are not displaying correctly, enable debug logging to diagnose the issue:

1. **Enable debug mode** in your setup:
```lua
require("file_history").setup({
  debug = true,
  -- ... other options
})
```

2. **Reproduce the issue** by opening a file history preview

3. **View the logs** with one of these commands:
```vim
:FileHistory debug        " Opens logs in a new buffer
:FileHistory debug_copy   " Copies logs to clipboard
:FileHistory debug_clear  " Clears the log buffer
```

4. **Programmatic access** (for scripts/debugging):
```lua
local fh = require("file_history")
local logs = fh.get_debug_logs()  -- Get logs as string
fh.show_debug_logs()              -- Open in buffer
fh.copy_debug_logs()              -- Copy to clipboard
```

The logs include:
- Git command execution and results
- File content retrieval (line counts, first/last lines)
- Diff generation (input lengths, output length, preview)
- Preview rendering (parsed line counts, type distribution)

## Development

### Running tests

This repo uses [busted](https://lunarmodules.github.io/busted/) for unit tests.

```bash
busted
```

### Running coverage

Coverage is powered by `luacov`.

```bash
luarocks install --local luacov
busted -r coverage
```

This produces `luacov.report.out` at the repo root.

## Related Projects

- [snacks.nvim](https://github.com/folke/snacks.nvim) - Required dependency for the picker UI
- [undotree](https://github.com/mbbill/undotree) - Vim's undo history visualizer
- [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim) - Git integration for buffers

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see LICENSE file for details

## Credits

- Inspired by local history features in JetBrains IDEs
- Diff rendering inspired by [snacks.nvim](https://github.com/folke/snacks.nvim) git_diff
- Built with [snacks.nvim](https://github.com/folke/snacks.nvim) picker framework
