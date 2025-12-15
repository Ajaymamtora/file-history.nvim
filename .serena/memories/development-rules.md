# file-history.nvim Development Rules

## Project Structure
- `lua/file_history/` - Main plugin source
  - `init.lua` - Plugin entry, picker configuration, user commands
  - `fh.lua` - Git operations, file backup/restore
  - `preview.lua` - Diff rendering, highlighting, display modes
  - `actions.lua` - User actions (revert, diff tabs, etc.)
- `spec/` - Busted test files with stubs in `spec/stubs/` and helpers in `spec/helpers/`

## Code Patterns

### Trailing Newline Handling
When working with file content or diff text:
- Use `vim.split(text, "\n", { plain = true, trimempty = true })` to avoid spurious empty lines
- When comparing file content with vim.diff, ensure both sides have consistent trailing newlines:
  ```lua
  vim.diff(table.concat(lines_a, '\n') .. '\n', table.concat(lines_b, '\n') .. '\n', opts)
  ```
- Git output often includes trailing empty strings - use `trim_trailing_empty()` helper in fh.lua

### Diff Parsing
- Strip +/- prefixes from diff lines for display; use highlighting to convey add/delete status
- Preserve empty lines in middle of content but trim trailing empty lines
- Handle "No newline at end of file" markers with `show_no_newline` option

## Testing

### Running Tests
```bash
busted --verbose              # Run all tests
busted spec/preview_spec.lua  # Run specific test file
```

### Test Patterns
- Test edge cases: empty files, single lines, changes at beginning/end
- Test special content: unicode, whitespace-only changes, long lines, special characters
- Test performance: large diffs, many hunks
- Test re-rendering: ensure previous state is cleared

### Test File Structure
```lua
describe("module_name", function()
  before_each(function()
    vim = test_env.bootstrap()
    module = require("module_name")
  end)
  describe("feature", function()
    it("does something specific", function()
      -- Arrange, Act, Assert
    end)
  end)
end)
```

## Dependencies
- Requires `folke/snacks.nvim` for picker and icons
- Uses `plenary.filetype` for filetype detection
