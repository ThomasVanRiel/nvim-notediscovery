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

## Installation

### lazy.nvim

```lua
{
  'yourusername/nvim-notediscovery',
  lazy = false,
  config = function()
    require('notediscovery').setup({
      url = "https://notes.example.com/api",  -- Required!
      default_folder = "inbox",                -- Optional
      cookies_file = "~/.notediscovery_cookies",  -- Optional
      quick_note_format = "%Y-%m-%d-%H%M%S",   -- Optional
    })
    
    -- Optional: Set up keybindings
    local keymap = vim.keymap.set
    keymap('n', '<leader>nl', ':NoteList<CR>', { desc = 'List notes' })
    keymap('n', '<leader>ns', ':NoteSearch<CR>', { desc = 'Search notes' })
    keymap('n', '<leader>nn', ':NoteNew<CR>', { desc = 'New note' })
    keymap('n', '<leader>no', ':NoteLoad<CR>', { desc = 'Open note' })
    keymap('v', '<leader>nq', '"+y:NoteQuick<CR>', { desc = 'Quick note from selection' })
  end
}
```


## Quick Start

1. **Configure** in your `init.lua`:
   ```lua
   require('notediscovery').setup({
     url = "https://notes.thomasvanriel.com/api"
   })
   ```

2. **Login** (one time):
   ```vim
   :NoteLogin
   ```
   Enter your password (hidden input). Session cookie saved for 7 days.

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
| `:NoteNew [path]` | Create a new note |
| `:NoteSave [path]` | Save current buffer as note |
| `:NoteSearch [query]` | Search notes (press Enter to load) |
| `:NoteQuick` | Create quick note from clipboard |
| `:NoteDelete [path]` | Delete a note |
| `:NoteGraph` | View note relationship graph |
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

## Configuration Options

```lua
require('notediscovery').setup({
  -- Required: Your NoteDiscovery API URL
  url = "https://notes.example.com/api",
  
  -- Optional: Cookie file location (default: ~/.notediscovery_cookies)
  cookies_file = vim.fn.expand("~/.notediscovery_cookies"),
  
  -- Optional: Default folder for quick notes (default: "inbox")
  default_folder = "inbox",
  
  -- Optional: Timestamp format for quick notes (default: "%Y-%m-%d-%H%M%S")
  quick_note_format = "%Y-%m-%d-%H%M%S",
  
  -- Optional: Enable debug mode (default: false)
  debug = false,
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

- Uses `curl` for HTTP requests to NoteDiscovery API
- Session authentication via cookie file
- Intercepts `:w` / `:wq` with `BufWriteCmd` to auto-save to API
- URL encodes paths to handle folders and special characters

## License

MIT

## Contributing

Issues and pull requests welcome!

## Related Projects

- [NoteDiscovery](https://github.com/gamosoft/NoteDiscovery) - The self-hosted notes backend
