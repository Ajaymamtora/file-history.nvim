# Undo Tree Integration Plan

## Executive Summary

This document outlines the plan to add Neovim's built-in undo tree as a second history source alongside the existing Git-based mechanism in `file-history.nvim`. Users will be able to choose one or both sources, with both enabled by default.

---

## 1. Research Findings

### 1.1 Neovim Undo Tree API

#### Core API: `vim.fn.undotree()`

Returns a dictionary with:

```lua
{
  seq_last = 15,      -- Highest undo sequence number
  seq_cur = 12,       -- Current position in undo tree
  time_cur = 1705678901,  -- Timestamp (use strftime() to format)
  save_last = 3,      -- Number of file writes
  save_cur = 2,       -- Current save position
  synced = 1,         -- Whether last undo block was synced
  entries = {         -- List of undo blocks
    {
      seq = 1,
      time = 1705678800,
      save = 1,           -- Optional: present if this was a save point
      newhead = true,     -- Optional: marks the newest entry
      curhead = true,     -- Optional: marks current position after undo
      alt = { ... },      -- Optional: alternate branches (undo tree branches)
    },
    -- ...
  }
}
```

#### Navigating to Specific Undo States

```lua
-- Jump to a specific undo sequence number
vim.cmd("undo " .. seq_number)

-- Or using Lua API
vim.cmd.undo(seq_number)
```

#### Getting Buffer Content at Undo State

The key insight from snacks.nvim's implementation is to use a **temporary buffer** to avoid modifying the user's actual buffer:

```lua
-- Create temp copy of buffer
local tmp_file = vim.fn.stdpath("cache") .. "/file-history-undo"
local tmp_undo = tmp_file .. ".undo"
local tmpbuf = vim.fn.bufadd(tmp_file)
vim.bo[tmpbuf].swapfile = false

-- Copy current content and undo history
vim.fn.writefile(vim.api.nvim_buf_get_lines(buf, 0, -1, false), tmp_file)
vim.fn.bufload(tmpbuf)

-- Save and restore undo history to temp buffer
vim.api.nvim_buf_call(buf, function()
  vim.cmd("silent wundo! " .. tmp_undo)
end)
vim.api.nvim_buf_call(tmpbuf, function()
  pcall(vim.cmd, "silent rundo " .. tmp_undo)
end)

-- Now navigate in temp buffer safely
vim.api.nvim_buf_call(tmpbuf, function()
  vim.cmd("noautocmd silent undo " .. entry.seq)
  local lines_at_state = vim.api.nvim_buf_get_lines(tmpbuf, 0, -1, false)
end)

-- Cleanup
vim.api.nvim_buf_delete(tmpbuf, { force = true })
vim.fn.delete(tmp_file)
vim.fn.delete(tmp_undo)
```

#### Undo Branches (Alternate Timelines)

When you undo and then make new changes, Vim creates a branch. The `alt` field in undo entries contains these alternate branches as nested lists. This creates a tree structure, not a linear history.

#### Persistent Undo

```lua
-- Enable persistent undo
vim.opt.undofile = true
vim.opt.undodir = vim.fn.stdpath("state") .. "/undo"

-- Manually save/restore undo history
vim.cmd("wundo " .. filepath)  -- Write undo file
vim.cmd("rundo " .. filepath)  -- Read undo file
```

### 1.2 Comparison: Git vs Undo Sources

| Aspect | Git Source | Undo Source |
|--------|-----------|-------------|
| **Persistence** | Always persistent (in git repo) | Session-only (unless `undofile` enabled) |
| **Scope** | All files, cross-session | Per-buffer, current session |
| **Granularity** | One entry per save | One entry per change block |
| **Branching** | Linear per file | True tree with branches |
| **Metadata** | Commit hash, timestamp, tags | Sequence number, timestamp, save points |
| **Storage** | External git repository | In-memory / undofile |
| **Cross-machine** | Portable via git | Local only |
| **Content Retrieval** | `git show hash:path` | Navigate undo tree, read buffer |

### 1.3 Current Plugin Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         init.lua                                │
│  ┌─────────────────┐    ┌─────────────────┐                    │
│  │ file_history_   │    │ file_history_   │                    │
│  │ finder()        │    │ files_finder()  │                    │
│  └────────┬────────┘    └────────┬────────┘                    │
│           │ calls                │ calls                        │
│           ▼                      ▼                              │
│  ┌─────────────────────────────────────────────────────────────┤
│  │                        fh.lua                               │
│  │  ┌───────────────────┐  ┌───────────────────┐              │
│  │  │ file_history()    │  │ get_file()        │              │
│  │  │ → git log         │  │ → git show        │              │
│  │  └───────────────────┘  └───────────────────┘              │
│  └─────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐    ┌─────────────────┐                    │
│  │ preview.lua     │    │ actions.lua     │                    │
│  │ → render_diff() │    │ → revert, diff  │                    │
│  └─────────────────┘    └─────────────────┘                    │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Proposed Architecture

### 2.1 Provider Abstraction

Create a provider interface that both Git and Undo sources implement:

```
┌─────────────────────────────────────────────────────────────────┐
│                         init.lua                                │
│  ┌─────────────────────────────────────────────────────────────┤
│  │                    Unified Picker                           │
│  │  finder = providers.get_history_items(sources)              │
│  │  preview = providers.get_content(item) → vim.diff()         │
│  └─────────────────────────────────────────────────────────────┤
│           │                                                     │
│           ▼                                                     │
│  ┌─────────────────────────────────────────────────────────────┤
│  │                   providers/init.lua                        │
│  │  ┌─────────────────┐    ┌─────────────────┐                │
│  │  │ git.lua         │    │ undo.lua        │                │
│  │  │ (existing fh)   │    │ (new)           │                │
│  │  └─────────────────┘    └─────────────────┘                │
│  └─────────────────────────────────────────────────────────────┤
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Provider Interface

```lua
---@class FileHistoryProvider
---@field name string  -- "git" or "undo"
---@field get_history fun(buf: number, filepath: string): HistoryItem[]
---@field get_content fun(item: HistoryItem): string[]
---@field can_revert fun(item: HistoryItem): boolean
---@field revert fun(item: HistoryItem, buf: number): boolean
---@field get_diff fun(item: HistoryItem, current_lines: string[]): string

---@class HistoryItem
---@field source "git"|"undo"  -- Which provider this came from
---@field id string            -- Unique identifier (hash or seq number)
---@field timestamp number     -- Unix timestamp
---@field time_ago string      -- Human readable "2 hours ago"
---@field date string          -- Formatted date
---@field label string         -- Display label (tag or "undo #N")
---@field is_save_point boolean -- Whether this was a file save
---@field branch_depth number   -- 0 for main timeline, >0 for branches
---@field text string          -- Searchable text for picker
```

### 2.3 New File Structure

```
lua/file_history/
├── init.lua              # Entry point, picker UI (modified)
├── fh.lua                # DEPRECATED: redirect to providers/git.lua
├── providers/
│   ├── init.lua          # Provider registry and unified interface
│   ├── git.lua           # Git provider (extracted from fh.lua)
│   └── undo.lua          # NEW: Undo tree provider
├── actions.lua           # Modified: use provider interface
├── preview.lua           # Unchanged: receives diff text
└── debug.lua             # Unchanged
```

---

## 3. Implementation Plan

### Phase 1: Refactor to Provider Pattern (Non-Breaking)

**Goal**: Extract Git logic into a provider without changing external behavior.

#### 3.1.1 Create Provider Interface

Create `lua/file_history/providers/init.lua`:

```lua
local M = {}

---@type table<string, FileHistoryProvider>
M.providers = {}

function M.register(name, provider)
  M.providers[name] = provider
end

function M.get_history(sources, buf, filepath)
  local items = {}
  for _, source in ipairs(sources) do
    local provider = M.providers[source]
    if provider then
      local provider_items = provider.get_history(buf, filepath)
      for _, item in ipairs(provider_items) do
        item.source = source
        table.insert(items, item)
      end
    end
  end
  -- Sort by timestamp descending
  table.sort(items, function(a, b) return a.timestamp > b.timestamp end)
  return items
end

function M.get_content(item)
  local provider = M.providers[item.source]
  return provider and provider.get_content(item) or {}
end

return M
```

#### 3.1.2 Extract Git Provider

Create `lua/file_history/providers/git.lua`:

- Move `FileHistory` table and methods from `fh.lua`
- Implement the provider interface
- Keep `fh.lua` as a thin wrapper for backward compatibility

#### 3.1.3 Update Init.lua

- Import providers module
- Modify finder functions to use provider interface
- Add source indicator to item format

**Estimated Effort**: 4-6 hours

### Phase 2: Implement Undo Provider

**Goal**: Add undo tree as a second history source.

#### 3.2.1 Create Undo Provider

Create `lua/file_history/providers/undo.lua`:

```lua
local M = {}

local dbg = require("file_history.debug")

-- Cache for undo tree traversal
local undo_cache = {}

---@class UndoHistoryItem
---@field seq number
---@field timestamp number
---@field is_save_point boolean
---@field branch_depth number

---Traverse undo tree and flatten to list
---@param entries vim.fn.undotree.entry[]
---@param depth number
---@param result UndoHistoryItem[]
local function traverse_undo_tree(entries, depth, result)
  for _, entry in ipairs(entries or {}) do
    -- Process alternate branches first (older)
    if entry.alt then
      traverse_undo_tree(entry.alt, depth + 1, result)
    end
    
    table.insert(result, {
      seq = entry.seq,
      timestamp = entry.time,
      is_save_point = entry.save ~= nil,
      branch_depth = depth,
    })
  end
end

---@param buf number
---@param filepath string
---@return HistoryItem[]
function M.get_history(buf, filepath)
  local tree = vim.fn.undotree(buf)
  local items = {}
  local raw_items = {}
  
  traverse_undo_tree(tree.entries, 0, raw_items)
  
  -- Convert to HistoryItem format
  for _, raw in ipairs(raw_items) do
    local time_ago = -- calculate from raw.timestamp
    table.insert(items, {
      source = "undo",
      id = tostring(raw.seq),
      seq = raw.seq,  -- Keep original for navigation
      timestamp = raw.timestamp,
      time_ago = time_ago,
      date = os.date("%Y-%m-%d %H:%M:%S", raw.timestamp),
      label = raw.is_save_point and "[saved]" or "",
      is_save_point = raw.is_save_point,
      branch_depth = raw.branch_depth,
      text = string.format("undo #%d %s", raw.seq, time_ago),
      -- Store buffer reference for content retrieval
      buf = buf,
    })
  end
  
  return items
end

---@param item HistoryItem
---@return string[]
function M.get_content(item)
  -- Use temporary buffer technique from snacks.nvim
  local buf = item.buf
  local tmp_file = vim.fn.stdpath("cache") .. "/file-history-undo-" .. buf
  local tmp_undo = tmp_file .. ".undo"
  
  -- Create temp buffer with current content
  local tmpbuf = vim.fn.bufadd(tmp_file)
  vim.bo[tmpbuf].swapfile = false
  vim.fn.writefile(vim.api.nvim_buf_get_lines(buf, 0, -1, false), tmp_file)
  vim.fn.bufload(tmpbuf)
  
  -- Transfer undo history
  vim.api.nvim_buf_call(buf, function()
    vim.cmd("silent wundo! " .. tmp_undo)
  end)
  vim.api.nvim_buf_call(tmpbuf, function()
    pcall(vim.cmd, "silent rundo " .. tmp_undo)
  end)
  
  -- Navigate to the undo state and capture content
  local lines = {}
  local ei = vim.o.eventignore
  vim.o.eventignore = "all"
  vim.api.nvim_buf_call(tmpbuf, function()
    vim.cmd("noautocmd silent undo " .. item.seq)
    lines = vim.api.nvim_buf_get_lines(tmpbuf, 0, -1, false)
  end)
  vim.o.eventignore = ei
  
  -- Cleanup
  vim.api.nvim_buf_delete(tmpbuf, { force = true })
  vim.fn.delete(tmp_file)
  vim.fn.delete(tmp_undo)
  
  return lines
end

---@param item HistoryItem
---@param buf number
function M.revert(item, buf)
  vim.api.nvim_buf_call(buf, function()
    vim.cmd("undo " .. item.seq)
  end)
end

return M
```

#### 3.2.2 Handle Undo-Specific Considerations

1. **Buffer Validity**: Undo history is buffer-local; must check buffer is still valid
2. **Performance**: Traversing large undo trees can be slow; implement lazy loading
3. **Branch Visualization**: Show branch depth in picker format (indentation or icon)
4. **Save Points**: Highlight entries that correspond to file saves

**Estimated Effort**: 6-8 hours

### Phase 3: Configuration and UI

**Goal**: Allow users to configure sources and improve UI.

#### 3.3.1 New Configuration Options

```lua
defaults = {
  -- Existing options...
  
  -- History sources configuration
  sources = {
    git = true,   -- Enable git source (default: true)
    undo = true,  -- Enable undo source (default: true)
  },
  
  -- How to display multiple sources
  display = {
    -- "merged": Single list sorted by time
    -- "grouped": Separate sections for each source
    -- "tabs": Separate tabs/pickers for each source
    mode = "merged",
    
    -- Show source indicator in picker
    show_source = true,
    
    -- Source-specific icons/prefixes
    source_icons = {
      git = "",
      undo = "",
    },
  },
  
  -- Undo-specific options
  undo = {
    -- Include undo branches (alternate timelines)
    include_branches = true,
    
    -- Only show save points (reduce noise)
    save_points_only = false,
    
    -- Maximum undo entries to show (0 = unlimited)
    max_entries = 100,
  },
}
```

#### 3.3.2 Update Picker Format

```lua
fhp.format = function(item)
  local ret = {}
  
  -- Source indicator
  if M.opts.display.show_source then
    local icon = M.opts.display.source_icons[item.source] or ""
    local hl = item.source == "git" and "GitSignsAdd" or "DiagnosticInfo"
    ret[#ret + 1] = { icon .. " ", hl }
  end
  
  -- Branch indicator for undo items
  if item.source == "undo" and item.branch_depth > 0 then
    ret[#ret + 1] = { string.rep("│ ", item.branch_depth), "Comment" }
  end
  
  -- Time and date
  ret[#ret + 1] = { str_prepare(item.time_ago or "", 16), "FileHistoryTime" }
  ret[#ret + 1] = { " " }
  ret[#ret + 1] = { str_prepare(item.date or "", 20), "FileHistoryDate" }
  ret[#ret + 1] = { " " }
  
  -- Label (tag for git, save indicator for undo)
  ret[#ret + 1] = { item.label or "", "FileHistoryTag" }
  
  return ret
end
```

**Estimated Effort**: 3-4 hours

### Phase 4: Actions and Integration

**Goal**: Ensure all actions work with both sources.

#### 3.4.1 Update Actions

Modify `actions.lua` to use provider interface:

```lua
fh_actions.revert_to_selected = function(item, data)
  local providers = require("file_history.providers")
  local provider = providers.providers[item.source]
  
  if provider and provider.revert then
    provider.revert(item, data.buf)
  end
end
```

#### 3.4.2 Source-Specific Actions

Some actions only make sense for certain sources:

| Action | Git | Undo |
|--------|-----|------|
| Revert | ✓ (set buffer lines) | ✓ (vim.cmd.undo) |
| Open in tab | ✓ | ✓ |
| Side-by-side diff | ✓ | ✓ |
| Yank additions | ✓ | ✓ |
| Delete history | ✓ | ✗ (not applicable) |
| Purge history | ✓ | ✗ (not applicable) |
| Tag/label | ✓ | ✗ (not applicable) |

**Estimated Effort**: 2-3 hours

### Phase 5: Testing and Documentation

#### 3.5.1 New Test Cases

```lua
-- spec/undo_provider_spec.lua
describe("undo provider", function()
  it("returns empty list for buffer with no undo history", function() end)
  it("returns correct entries from undo tree", function() end)
  it("handles undo branches correctly", function() end)
  it("retrieves content at specific undo state", function() end)
  it("reverts buffer to undo state", function() end)
  it("respects max_entries limit", function() end)
  it("filters to save_points_only when configured", function() end)
end)

-- spec/providers_spec.lua  
describe("provider registry", function()
  it("merges items from multiple sources", function() end)
  it("sorts merged items by timestamp", function() end)
  it("respects source enable/disable config", function() end)
end)
```

#### 3.5.2 Documentation Updates

- Update README.md with new configuration options
- Add section explaining undo vs git sources
- Add troubleshooting for undo-specific issues
- Add examples for common configurations

**Estimated Effort**: 3-4 hours

---

## 4. Technical Challenges and Mitigations

### 4.1 Undo State Content Retrieval Performance

**Challenge**: Navigating the undo tree and extracting content is expensive.

**Mitigations**:
1. Use temporary buffer (avoids modifying user's buffer)
2. Lazy-load content only when preview is requested
3. Cache recently accessed undo states
4. Batch-resolve items (like snacks.nvim does)

### 4.2 Undo Tree Validity

**Challenge**: Undo tree can change while picker is open (user makes edits).

**Mitigations**:
1. Snapshot undo tree state when picker opens
2. Detect invalidation and show warning
3. Optionally refresh on focus

### 4.3 Branch Visualization

**Challenge**: Undo tree can have complex branching that's hard to display linearly.

**Mitigations**:
1. Show branch depth as indentation
2. Add visual markers for branch points
3. Optional: filter to main branch only

### 4.4 Source Identification in Actions

**Challenge**: Actions need to know which provider handles an item.

**Mitigations**:
1. Store `source` field on every item
2. Provider registry returns correct provider by name
3. Actions gracefully handle unsupported operations

---

## 5. Migration Path

### 5.1 Backward Compatibility

- `fh.lua` remains as thin wrapper, deprecated but functional
- Default config enables both sources (no behavior change for git-only users)
- All existing functions continue to work

### 5.2 Deprecation Warnings

```lua
-- In fh.lua
local function deprecated(fn_name)
  vim.notify_once(
    "[file-history] fh." .. fn_name .. "() is deprecated. " ..
    "Use require('file_history.providers').providers.git." .. fn_name .. "()",
    vim.log.levels.WARN
  )
end
```

---

## 6. Future Enhancements

### 6.1 Additional Providers (Post-MVP)

- **LSP Document History**: For servers that support document versioning
- **External Backup**: Integration with rsync/restic/borg snapshots
- **Cloud Sync**: Google Drive/Dropbox version history

### 6.2 Advanced Features

- **Diff Between Any Two Points**: Select two history items and diff them
- **Search Within History**: Full-text search across all historical versions
- **Visual Undo Tree**: ASCII art or floating window showing tree structure
- **Undo Branch Naming**: Let users name branches for easier navigation

---

## 7. Timeline Summary

| Phase | Description | Effort | Dependencies |
|-------|-------------|--------|--------------|
| 1 | Refactor to Provider Pattern | 4-6h | None |
| 2 | Implement Undo Provider | 6-8h | Phase 1 |
| 3 | Configuration and UI | 3-4h | Phase 2 |
| 4 | Actions and Integration | 2-3h | Phase 3 |
| 5 | Testing and Documentation | 3-4h | Phase 4 |

**Total Estimated Effort**: 18-25 hours

---

## 8. Acceptance Criteria

- [ ] Both git and undo sources enabled by default
- [ ] User can disable either source via configuration
- [ ] Picker shows source indicator for each item
- [ ] Undo items show branch depth visually
- [ ] Save points are highlighted in undo source
- [ ] All existing actions work with git source (no regression)
- [ ] Revert, diff, and view actions work with undo source
- [ ] Performance: Picker opens in <500ms for 100 undo entries
- [ ] Tests cover all new functionality
- [ ] README documents new features

---

## Appendix A: Reference Implementations

### A.1 snacks.nvim Undo Picker

- Location: `lua/snacks/picker/source/vim.lua` (function `M.undo`)
- Key technique: Temporary buffer for safe undo navigation
- Batch resolution for performance

### A.2 telescope-undo.nvim

- Location: `lua/telescope-undo/init.lua`
- Key technique: Traverses undo tree recursively
- Builds diff on-demand

### A.3 jiaoshijie/undotree

- Location: `lua/undotree/undotree.lua`
- Key technique: Graph-based visualization
- Tracks parent-child relationships

---

## Appendix B: Neovim Undo API Reference

```lua
-- Get undo tree for current buffer
vim.fn.undotree()

-- Get undo tree for specific buffer
vim.fn.undotree(bufnr)

-- Navigate to specific undo state
vim.cmd("undo " .. seq)

-- Save undo history to file
vim.cmd("wundo " .. filepath)

-- Load undo history from file
vim.cmd("rundo " .. filepath)

-- Check if undo is possible
vim.fn.undotree().seq_cur > 0

-- Get current change number (for tracking)
vim.fn.changenr()
```
