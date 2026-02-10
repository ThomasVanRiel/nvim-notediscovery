# nvim-notediscovery

Neovim integration for [NoteDiscovery](https://github.com/gamosoft/NoteDiscovery) - manage your self-hosted markdown notes from within Neovim.

## Features

- 🔐 Secure login with hidden password input
- 📝 Edit notes with `:w` / `:wq` (auto-saves to NoteDiscovery)
- 🔍 Full-text search across all notes
- 📁 Browse notes by folder with interactive list
- ⚡ Quick note creation from clipboard/selection
- 🖼️ Inline image rendering with automatic downloading and caching
- 🔄 Persistent last note - `:NoteLoadLast` works across Neovim restarts
- 📢 Non-blocking notifications (errors only prompt for Enter)
- 🗂️ Clean data directory - all plugin files in one location
- 🐛 Debug mode for troubleshooting

## Requirements

- Neovim 0.8+
- `curl` (for API requests)
- A running [NoteDiscovery](https://github.com/gamosoft/NoteDiscovery) instance

## Optional Dependencies

- [image.nvim](https://github.com/3rd/image.nvim) - For inline image rendering (requires Kitty, iTerm2, WezTerm, or compatible terminal with image protocol support)

## Installation

### lazy.nvim

```lua
{
  'ThomasVanRiel/nvim-notediscovery',
  lazy = false,
  dependencies = {
    {
      '3rd/image.nvim',
      opts = {
        backend = "kitty",  -- or "ueberzug" for other terminals
        integrations = {
          markdown = {
            enabled = true,
            clear_in_insert_mode = true,
            download_remote_images = true,
            only_render_image_at_cursor = false,
            filetypes = { "markdown", "vimwiki" },
            resolve_image_path = function(document_path, image_path, fallback)
              -- For notediscovery buffers, resolve images from cache
              if document_path:match("^notediscovery://") then
                local note_path = document_path:gsub("^notediscovery://", "")
                local folder = vim.fn.fnamemodify(note_path, ":h")
                if folder == "." or folder == "" then
                  folder = "root"
                end
                
                -- Extract just the filename from image_path
                -- Handle both "image.png" and "_attachments/image.png" formats
                local image_name = image_path:match("([^/]+)$") or image_path
                -- Also handle wiki-style ![[_attachments/image.png]]
                image_name = image_name:gsub("^_attachments/", "")
                
                -- Build cached path - format is {folder}_{filename}
                -- Convert slashes to underscores for nested folders
                local cache_dir = vim.fn.stdpath('data') .. '/notediscovery/images'
                local folder_name = folder:gsub("/", "_")
                local cached_file = folder_name .. "_" .. image_name
                local cached_path = cache_dir .. "/" .. cached_file
                
                -- Debug logging (uncomment to troubleshoot)
                -- vim.notify("Resolving: " .. image_path .. " -> " .. cached_path, vim.log.levels.INFO)
                -- vim.notify("Exists: " .. tostring(vim.fn.filereadable(cached_path) == 1), vim.log.levels.INFO)
                
                -- Check if cached file exists
                if vim.fn.filereadable(cached_path) == 1 then
                  return cached_path
                end
              end
              
              -- Fallback to default resolution
              return fallback(document_path, image_path)
            end,
                
                -- Check if cached file exists
                if vim.fn.filereadable(cached_path) == 1 then
                  return cached_path
                end
              end
              
              -- Fallback to default resolution
              return fallback(document_path, image_path)
            end,
          },
        },
        max_width = nil,
        max_height = nil,
        max_width_window_percentage = nil,
        max_height_window_percentage = 50,
        window_overlap_clear_enabled = true,  -- Hide images when overlapped by windows
        window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "" },
        editor_only_render_when_focused = false,
        tmux_show_only_in_active_window = false,
        hijack_file_patterns = { "*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp" },
      },
    },
  },
  config = function()
    require('notediscovery').setup({
      url = "https://notes.example.com/api",  -- Required!
      default_folder = "inbox",                -- Optional
      enable_images = true,                     -- Optional: enable image rendering
      auto_render_images = true,                -- Optional: auto-render on load
    })
    
    -- Optional: Set up keybindings
    local keymap = vim.keymap.set
    keymap('n', '<leader>nl', ':NoteList<CR>', { desc = 'List notes' })
    keymap('n', '<leader>ns', ':NoteSearch<CR>', { desc = 'Search notes' })
    keymap('n', '<leader>nn', ':NoteNew<CR>', { desc = 'New note' })
    keymap('n', '<leader>no', ':NoteLoad<CR>', { desc = 'Open note' })
    keymap('n', '<leader>nr', ':NoteLoadLast<CR>', { desc = 'Reload last note' })
    keymap('v', '<leader>nq', '"+y:NoteQuick<CR>', { desc = 'Quick note from selection' })
    keymap('n', '<leader>ni', ':NoteImagesToggle<CR>', { desc = 'Toggle images' })
  end
}
```

### Using Development Branch

To test the latest features before they're merged to main:

```lua
{
  'ThomasVanRiel/nvim-notediscovery',
  branch = 'dev',  -- Use dev branch for latest features
  lazy = false,
  -- ... rest of config
}
```

Or use a local development copy:

```lua
{
  'nvim-notediscovery',
  dir = '~/path/to/nvim-notediscovery',  -- Local path
  lazy = false,
  -- ... rest of config
}
```

## Quick Start

1. **Configure** in your `init.lua`:
   ```lua
   require('notediscovery').setup({
     url = "https://notes.example.com/api"
   })
   ```

2. **Login** (one time):
   ```vim
   :NoteLogin
   ```
   Enter your password (hidden input). Session cookie saved to Neovim's data directory for 7 days.

3. **Browse notes**:
   ```vim
   :NoteList
   ```
   Navigate with `j`/`k`, press `<Enter>` to load, `q` to quit.

4. **Edit and save**:
   - Make changes to the note
   - Save with `:w` or `:wq` (auto-syncs to NoteDiscovery)

5. **Quick access to last note**:
   ```vim
   :NoteLoadLast
   ```
   Reloads your most recently opened note - persists across Neovim restarts!

## Commands

| Command | Description |
|---------|-------------|
| `:NoteLogin` | Authenticate to NoteDiscovery |
| `:NoteList` | Browse all notes (press Enter to load) |
| `:NoteLoad [path]` | Load a specific note |
| `:NoteLoadLast` | Reload the last loaded note |
| `:NoteNew [path]` | Create a new note |
| `:NoteSave [path]` | Save current buffer as note |
| `:NoteSearch [query]` | Search notes (press Enter to load) |
| `:NoteQuick` | Create quick note from clipboard |
| `:NoteDelete [path]` | Delete a note |
| `:NoteGraph` | View note relationship graph |
| `:NoteImagesShow` | Render inline images in current note |
| `:NoteImagesHide` | Hide inline images in current note |
| `:NoteImagesToggle` | Toggle inline images on/off |
| `:NoteTest` | Test API connection |
| `:NoteLoadDebug [path]` | Load note with debug output |

## Usage Examples

### Create a new note
```vim
:NoteNew inbox/my-idea.md
" Edit the content...
:w    " Save it!
```

### Search and open
```vim
:NoteSearch meeting
" Press <Enter> on a result to load it
" Edit...
:wq   " Save and close
```

### Quick note from selection
```vim
" Visual select some text
:'<,'>y
:NoteQuick
" Creates a new note in inbox/ with timestamp
```

### Browse all notes
```vim
:NoteList
" Navigate with j/k
" Press <Enter> to open
" Press q to close
```

### Working with images
```vim
" Images in ![[image.png]] or ![alt](image.png) format are auto-rendered
" if image.nvim is installed
:NoteImagesToggle  " Toggle images on/off
:NoteImagesHide    " Hide images
:NoteImagesShow    " Show images
```

## Configuration Options

```lua
require('notediscovery').setup({
  -- Required: Your NoteDiscovery API URL
  url = "https://notes.example.com/api",
  
  -- Optional: Data directory for plugin files (default: vim.fn.stdpath('data')/notediscovery)
  -- This stores cookies, logs, image cache, and last note state
  data_dir = vim.fn.stdpath('data') .. '/notediscovery',
  
  -- Optional: Cookie file location (default: {data_dir}/cookies)
  cookies_file = vim.fn.stdpath('data') .. '/notediscovery/cookies',
  
  -- Optional: Default folder for quick notes (default: "inbox")
  default_folder = "inbox",
  
  -- Optional: Timestamp format for quick notes (default: "%Y-%m-%d-%H%M%S")
  quick_note_format = "%Y-%m-%d-%H%M%S",
  
  -- Optional: Enable inline image rendering (default: true)
  enable_images = true,
  
  -- Optional: Auto-render images on note load (default: true)
  auto_render_images = true,
  
  -- Optional: Image cache directory (default: {data_dir}/images)
  image_cache_dir = vim.fn.stdpath('data') .. '/notediscovery/images',
  
  -- Optional: Log file location (default: {data_dir}/notediscovery.log)
  log_file = vim.fn.stdpath('data') .. '/notediscovery/notediscovery.log',
  
  -- Optional: Enable debug mode (default: false)
  debug = false,
  
  -- Optional: Automatically prompt for login on 401 errors (default: false)
  auto_login = false,
})
```

**Note about notifications:** Info and success messages appear briefly without blocking (no Enter press needed). Only error messages require acknowledgment to ensure you see important issues.

### Image Support

**Requirements:**
- Install [image.nvim](https://github.com/3rd/image.nvim) plugin
- Use a compatible terminal with image protocol support:
  - ✅ **Kitty** (Linux/macOS) - Best support
  - ✅ **WezTerm** (Linux/macOS/Windows WSL2)
  - ✅ **iTerm2** (macOS)
  - ✅ **Ueberzug++** (Linux, requires external tool)
  - ❌ **Windows Terminal** - Not supported (yet)
  - ❌ **CMD/PowerShell** - Not supported

**Supported syntax:**
- Wiki-style: `![[image.png]]`
- Standard markdown: `![alt text](image.png)`

**Supported formats:** PNG, JPG, JPEG, GIF, BMP, WEBP

**Image.nvim Configuration:**

**Important:** You must include the `resolve_image_path` function shown in the Installation section above. This custom function tells image.nvim where to find the cached images for virtual notediscovery buffers.

Choose your backend based on terminal:

```lua
-- For Kitty terminal
backend = "kitty"

-- For other Linux terminals with ueberzug installed
backend = "ueberzug"
```

**Key features:**
- **Automatic downloading**: Images fetched from `/api/media/{folder}/_attachments/{image}`
- **Caching**: Downloaded images cached in `{data_dir}/images/` for fast reloads
- **Auto-rendering**: Images appear automatically when loading notes
- **Hide on edit**: Images disappear when cursor is on the line (in insert mode)
- **Path rewriting**: Plugin converts wiki-style links to absolute paths for image.nvim

**How it works:**
1. Plugin detects image syntax in markdown: `![[image.png]]`
2. Downloads image from API to local cache
3. image.nvim's custom `resolve_image_path` function intercepts path resolution
4. Function returns cached path: `~/.local/share/nvim/notediscovery/images/folder_image.png`
5. image.nvim's markdown integration renders the image inline
6. Image hides when you edit that line, reappears when cursor moves away
7. **Original markdown remains unchanged** - no path rewriting in buffer

**Usage:**
```vim
:NoteLoad my-note.md        " Images render automatically
:NoteImagesToggle           " Toggle all images on/off
:NoteImagesHide             " Hide all images
:NoteImagesShow             " Show all images
```

**Image positioning note:** If images appear at wrong positions with wrapped lines, consider disabling line wrap for markdown:
```lua
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function()
    vim.opt_local.wrap = false
  end,
})
```

## Troubleshooting

### Connection issues
```vim
:NoteTest
```
This checks:
- Server reachability
- Authentication status
- API endpoint availability

### Not authenticated error
```vim
:NoteLogin
```
Login again if your session expired (7 day default).

### Login fails with HTTP 301
The plugin now automatically follows redirects. If still failing:
- Check your URL format: `http://localhost:8000/api` (with `/api` suffix)
- Ensure the NoteDiscovery server is running
- Try the full URL with protocol: `http://` or `https://`

### Images not showing

**Step-by-step debugging:**

1. **Check if image.nvim is installed and configured:**
   ```vim
   :lua print(vim.inspect(package.loaded['image']))
   ```
   Should not be `nil`.

2. **Check terminal compatibility:**
   - Windows: Only works in WSL2 with Kitty/WezTerm
   - Linux: Use Kitty or install ueberzug
   - macOS: Use Kitty or iTerm2

3. **Verify images are enabled:**
   ```vim
   :lua print(require('notediscovery').config.enable_images)
   ```
   Should return `true`.

4. **Check if images were downloaded:**
   ```vim
   :lua print(require('notediscovery').config.image_cache_dir)
   ```
   Then check that directory in your terminal:
   ```bash
   ls ~/.local/share/nvim/notediscovery/images/
   ```
   You should see cached image files like `folder_image.png`.

5. **Enable debug logging in resolve_image_path:**
   In your image.nvim config, uncomment these lines:
   ```lua
   -- print("Resolving: " .. image_path .. " -> " .. cached_path)
   -- print("Exists: " .. tostring(vim.fn.filereadable(cached_path) == 1))
   ```
   Then reload a note and watch the output to see what paths are being resolved.

6. **Verify buffer name format:**
   ```vim
   :lua print(vim.api.nvim_buf_get_name(0))
   ```
   Should show `notediscovery://folder/note.md` format.

7. **Check image detection:**
   With a note open, run:
   ```vim
   :lua local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false); local images = require('notediscovery').find_image_links(lines); print(vim.inspect(images))
   ```
   This shows if the plugin detected images in your note.

8. **Enable plugin debug mode:**
   ```vim
   :lua require('notediscovery').config.debug = true
   :NoteLoad your-note.md
   :lua print(vim.fn.readfile(require('notediscovery').config.log_file))
   ```
   Check the log for image download errors.

9. **Manually test path resolution:**
   ```vim
   :lua local resolve = require('image').options.integrations.markdown.resolve_image_path; print(resolve("notediscovery://inbox/test.md", "image.png", function(d,p) return p end))
   ```
   Should return the cached path if the image exists.

10. **Check image.nvim setup:**
    If you see "image.nvim is not setup", add `opts = {...}` to your image.nvim dependency config (see Installation section).

11. **Force re-render:**
    ```vim
    :NoteImagesHide
    :NoteImagesShow
    ```
    Or reload the buffer: `:edit`

### Images at wrong position
If images appear shifted with wrapped lines:
```lua
-- Disable line wrapping in markdown
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function()
    vim.opt_local.wrap = false
  end,
})
```

### Image cache location
Clear cached images if needed:
```bash
rm -rf ~/.local/share/nvim/notediscovery/images/
```
Images will be re-downloaded on next note load.

### Debug a specific request
```vim
:NoteLoadDebug my-note.md
```
Shows the exact curl command and server response.

### Check configuration
```vim
:lua print(vim.inspect(require('notediscovery').config))
```

### View debug log
```vim
:lua print(vim.fn.readfile(require('notediscovery').config.log_file))
```

## How It Works

### Data Storage
- All plugin data stored in a dedicated directory: `vim.fn.stdpath('data')/notediscovery/`
  - **Linux/macOS**: `~/.local/share/nvim/notediscovery/`
  - **Windows**: `~/AppData/Local/nvim-data/notediscovery/`
- Contains: cookies, logs, image cache, and last note state
- Keeps your home directory clean and organized

### API Communication
- Uses `curl` for HTTP requests to NoteDiscovery API
- Session authentication via cookie file (7-day default expiration)
- Supports HTTP redirects (`-L` flag for 301/302)
- URL encodes paths to handle folders and special characters

### Buffer Management
- Virtual buffers with `buftype=acwrite` (not backed by real files)
- Intercepts `:w` / `:wq` with `BufWriteCmd` autocmd to auto-save to API
- Buffer names: `notediscovery://{path}` for display
- Filetype set to `markdown` for syntax highlighting

### Persistent State
- **Last loaded note**: Saved to `{data_dir}/last_note` file
- `:NoteLoadLast` works even after Neovim restarts
- Automatically loads previous note path on plugin initialization

### Notifications
- **Info/Success messages**: Non-blocking, appear briefly (no Enter press needed)
- **Error messages**: Block and require Enter press to ensure visibility
- **Warnings**: Non-blocking but visually distinct
- Uses `vim.api.nvim_echo()` for non-blocking messages

### Image Handling
- Downloads images from `/api/media/` endpoint on note load
- Caches to prevent repeated downloads
- Uses image.nvim's custom `resolve_image_path` hook to map image names to cached paths
- Original markdown syntax remains unchanged in buffer
- Delegates rendering to image.nvim's markdown integration

## License

MIT

## Contributing

Issues and pull requests welcome!

## Related Projects

- [NoteDiscovery](https://github.com/gamosoft/NoteDiscovery) - The self-hosted notes backend
