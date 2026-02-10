# nvim-notediscovery

Neovim integration for [NoteDiscovery](https://github.com/gamosoft/NoteDiscovery) - manage your self-hosted markdown notes from within Neovim.

## Features

- 🔐 Secure login with hidden password input
- 📝 Edit notes with `:w` / `:wq` (auto-saves to NoteDiscovery)
- 🔍 Full-text search across all notes
- 📁 Browse notes by folder with interactive list
- ⚡ Quick note creation from clipboard/selection
- 🌐 View note graph (wikilink connections)
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
    '3rd/image.nvim',  -- Optional: for inline image rendering
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
})
```

### Image Support

**Requirements:**
- Install [image.nvim](https://github.com/3rd/image.nvim) plugin
- Use a compatible terminal: Kitty, iTerm2, WezTerm, or terminals with image protocol support

**Supported syntax:**
- Wiki-style: `![[image.png]]`
- Standard markdown: `![alt text](image.png)`

**Supported formats:** PNG, JPG, JPEG, GIF, BMP, WEBP

**How it works:**
- Images are fetched from `{note_folder}/_attachments/` via the `/api/media/` endpoint
- Downloaded images are cached in `{data_dir}/images/` for faster subsequent loads
- Images render automatically when loading notes (configurable with `auto_render_images`)
- Use `:NoteImagesToggle` to show/hide images in the current buffer

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

### Debug a specific request
```vim
:NoteLoadDebug my-note.md
```
Shows the exact curl command and server response.

### Check configuration
```vim
:lua print(vim.inspect(require('notediscovery').config))
```

## How It Works

- All plugin data stored in a dedicated directory: `vim.fn.stdpath('data')/notediscovery/` (e.g., `~/.local/share/nvim/notediscovery/` on Linux)
- Uses `curl` for HTTP requests to NoteDiscovery API
- Session authentication via cookie file
- Intercepts `:w` / `:wq` with `BufWriteCmd` to auto-save to API
- URL encodes paths to handle folders and special characters
- Last loaded note is persisted across Neovim restarts

## License

MIT

## Contributing

Issues and pull requests welcome!

## Related Projects

- [NoteDiscovery](https://github.com/gamosoft/NoteDiscovery) - The self-hosted notes backend
