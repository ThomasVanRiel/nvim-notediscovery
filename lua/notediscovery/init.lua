-- NoteDiscovery API Integration for Neovim
-- Usage in init.lua:
--
-- require('notediscovery').setup({
--   url = "https://notes.example.com/api",  -- Required!
--   default_folder = "inbox",               -- Optional
--   auto_login = true,                      -- Optional: Auto-prompt for password on session expiry
-- })
--
-- Then run :NoteLogin to authenticate (password will be hidden)
-- With auto_login enabled, you'll be prompted automatically when your session expires

local M = {}

-- Track last loaded note for quick reload
local last_loaded_note = nil

-- Data directory for storing plugin data
local data_dir = vim.fn.stdpath('data') .. '/notediscovery'

-- Configuration
M.config = {
  url = nil, -- Required: Must be set via setup()
  data_dir = data_dir,
  cookies_file = data_dir .. '/cookies',
  default_folder = "inbox",
  quick_note_format = "%Y-%m-%d-%H%M%S", -- strftime format for quick notes
  log_file = data_dir .. '/notediscovery.log',
  auto_login = false, -- Automatically prompt for login on 401 errors
  enable_images = true, -- Enable inline image rendering with image.nvim
  auto_render_images = true, -- Automatically render images when loading notes
  image_cache_dir = data_dir .. '/images', -- Cache directory for downloaded images
  last_note_file = data_dir .. '/last_note', -- File to store last loaded note path
}

-- Logging function
local function log(message, level)
  level = level or vim.log.levels.INFO
  
  -- Always write to log file if debug is enabled
  if M.config.debug or M.config.log_file then
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local log_level = ({"TRACE", "DEBUG", "INFO", "WARN", "ERROR"})[level] or "INFO"
    local log_line = string.format("[%s] [%s] %s\n", timestamp, log_level, message)
    
    local file = io.open(M.config.log_file, "a")
    if file then
      file:write(log_line)
      file:close()
    end
  end
  
  -- Also show in Neovim
  vim.notify(message, level)
end

-- Notification wrapper: only ERROR level prompts for Enter
local function notify(message, level)
  level = level or vim.log.levels.INFO
  
  if level == vim.log.levels.ERROR then
    -- Errors require Enter press
    vim.notify(message, level)
  else
    -- Info/Warn messages don't block
    vim.api.nvim_echo({{message, level == vim.log.levels.WARN and "WarningMsg" or "None"}}, false, {})
  end
end

-- Save last loaded note to file
local function save_last_note(note_path)
  -- Ensure data directory exists
  vim.fn.mkdir(M.config.data_dir, "p")
  
  local file = io.open(M.config.last_note_file, "w")
  if file then
    file:write(note_path)
    file:close()
  end
end

-- Load last loaded note from file
local function load_last_note_from_file()
  local file = io.open(M.config.last_note_file, "r")
  if file then
    local note_path = file:read("*all")
    file:close()
    if note_path and note_path ~= "" then
      last_loaded_note = note_path
    end
  end
end

-- Setup function to override defaults
function M.setup(opts)
  if not opts or not opts.url then
    notify("NoteDiscovery: 'url' is required in setup()", vim.log.levels.ERROR)
    return
  end
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  
  -- Ensure data directory exists
  vim.fn.mkdir(M.config.data_dir, "p")
  
  -- Load last note from file
  load_last_note_from_file()
  
  -- Check if image.nvim is available
  local has_image = pcall(require, "image")
  M.config.enable_images = M.config.enable_images and has_image
  
  -- Register debug commands if debug mode is enabled
  if M.config.debug then
    vim.api.nvim_create_user_command("NoteTest", function()
      M.test_connection()
    end, {})
    
    vim.api.nvim_create_user_command("NoteLoadDebug", function(args)
      M.load_note(args.args, true)
    end, { nargs = "?", complete = "file" })
    
    vim.api.nvim_create_user_command("NoteSearchDebug", function(args)
      M.search_notes(args.args, true)
    end, { nargs = "?" })
    
    vim.api.nvim_create_user_command("NoteViewLog", function()
      M.view_log()
    end, {})
    
    vim.api.nvim_create_user_command("NoteClearLog", function()
      M.clear_log()
    end, {})
  end
end

-- Check if URL is configured
local function check_config()
  if not M.config.url then
    notify("NoteDiscovery not configured. Call setup() with 'url' first", vim.log.levels.ERROR)
    return false
  end
  return true
end

-- URL encode a string
local function url_encode(str)
  if str then
    str = string.gsub(str, "\n", "\r\n")
    str = string.gsub(str, "([^%w%-%.%_%~%/])", function(c)
      return string.format("%%%02X", string.byte(c))
    end)
  end
  return str
end

-- Find image links in buffer lines
-- Supports both ![[image.png]] (wiki-style) and ![alt](image.png) (standard markdown)
function M.find_image_links(lines)
  local images = {}
  local image_extensions = {"png", "jpg", "jpeg", "gif", "bmp", "webp"}
  
  for line_num, line in ipairs(lines) do
    -- Match wiki-style: ![[image.png]]
    for image_name in line:gmatch("!%[%[([^%]]+)%]%]") do
      -- Check if it has an image extension
      local ext = image_name:match("%.([^%.]+)$")
      if ext then
        for _, valid_ext in ipairs(image_extensions) do
          if ext:lower() == valid_ext then
            local col_start = line:find("!%[%[" .. vim.pesc(image_name) .. "%]%]")
            table.insert(images, {
              name = image_name,
              line = line_num,
              col_start = col_start,
            })
            break
          end
        end
      end
    end
    
    -- Match standard markdown: ![alt](image.png)
    for image_name in line:gmatch("!%[[^%]]*%]%(([^%)]+)%)") do
      local ext = image_name:match("%.([^%.]+)$")
      if ext then
        for _, valid_ext in ipairs(image_extensions) do
          if ext:lower() == valid_ext then
            local col_start = line:find("!%[[^%]]*%]%(" .. vim.pesc(image_name) .. "%)")
            table.insert(images, {
              name = image_name,
              line = line_num,
              col_start = col_start,
            })
            break
          end
        end
      end
    end
  end
  
  return images
end

-- Resolve attachment URL based on note path and image name
function M.resolve_attachment_url(note_path, image_name)
  local folder = vim.fn.fnamemodify(note_path, ":h")
  
  -- Handle root case where folder is "." or empty
  if folder == "." or folder == "" then
    folder = ""
  end
  
  -- Build media path: {folder}/_attachments/{image_name}
  local media_path
  if folder == "" then
    media_path = "_attachments/" .. image_name
  else
    media_path = folder .. "/_attachments/" .. image_name
  end
  
  -- Build full URL: remove /api suffix if present, then add /api/media/
  local base_url = M.config.url:gsub("/api$", "")
  return base_url .. "/api/media/" .. url_encode(media_path)
end

-- Download attachment to local cache
function M.download_attachment(image_url, image_name, note_path)
  -- Ensure cache directory exists
  vim.fn.mkdir(M.config.image_cache_dir, "p")
  
  -- Generate safe cache filename
  local folder_name = vim.fn.fnamemodify(note_path, ":h:t")
  if folder_name == "." or folder_name == "" then
    folder_name = "root"
  end
  local cache_file = folder_name .. "_" .. image_name
  local cache_path = M.config.image_cache_dir .. "/" .. cache_file
  
  -- Check if already cached and recent (within last 24 hours)
  local stat = vim.loop.fs_stat(cache_path)
  if stat and stat.mtime then
    local age = os.time() - stat.mtime.sec
    if age < 86400 then  -- 24 hours
      if M.config.debug then
        log("Using cached image: " .. cache_path, vim.log.levels.DEBUG)
      end
      return cache_path
    end
  end
  
  -- Download with curl
  local cmd = string.format(
    'curl -b %s -s -o %s %s',
    M.config.cookies_file,
    vim.fn.shellescape(cache_path),
    vim.fn.shellescape(image_url)
  )
  
  if M.config.debug then
    log("Downloading image: " .. cmd, vim.log.levels.DEBUG)
  end
  
  local exit_code = vim.fn.system(cmd)
  
  if vim.v.shell_error == 0 then
    -- Verify the file was actually downloaded
    local downloaded_stat = vim.loop.fs_stat(cache_path)
    if downloaded_stat and downloaded_stat.size > 0 then
      return cache_path
    else
      if M.config.debug then
        log("Downloaded file is empty: " .. cache_path, vim.log.levels.WARN)
      end
      return nil
    end
  else
    if M.config.debug then
      log("Failed to download image: " .. image_url, vim.log.levels.ERROR)
    end
    return nil
  end
end

-- Render images in buffer
function M.render_images(bufnr, note_path)
  -- Check if images are enabled
  if not M.config.enable_images then
    return
  end
  
  -- Check if image.nvim is available
  local has_image, image_nvim = pcall(require, "image")
  if not has_image then
    return
  end
  
  -- Handle current buffer if bufnr is 0
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  
  -- Get note path from buffer variable if not provided
  if not note_path then
    note_path = vim.b[bufnr].notediscovery_path
    if not note_path then
      if M.config.debug then
        log("No note path found for buffer " .. bufnr, vim.log.levels.WARN)
      end
      return
    end
  end
  
  -- Get buffer lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  
  -- Find all image links
  local images = M.find_image_links(lines)
  
  if #images == 0 then
    return
  end
  
  -- Initialize storage for rendered images
  if not vim.b[bufnr].notediscovery_images then
    vim.b[bufnr].notediscovery_images = {}
  end
  
  -- Render each image
  for _, img_info in ipairs(images) do
    local success, result = pcall(function()
      -- Resolve URL
      local image_url = M.resolve_attachment_url(note_path, img_info.name)
      
      -- Download to cache
      local local_path = M.download_attachment(image_url, img_info.name, note_path)
      
      if local_path then
        -- Try to create and render the image
        local image = image_nvim.from_file(local_path, {
          buffer = bufnr,
          with_virtual_padding = true,
        })
        
        if image then
          image:render()
          table.insert(vim.b[bufnr].notediscovery_images, image)
          
          if M.config.debug then
            log("Rendered image: " .. img_info.name .. " at line " .. img_info.line, vim.log.levels.INFO)
          end
        end
      else
        if M.config.debug then
          log("Failed to download: " .. img_info.name, vim.log.levels.WARN)
        end
      end
    end)
    
    if not success and M.config.debug then
      log("Error rendering image " .. img_info.name .. ": " .. tostring(result), vim.log.levels.ERROR)
    end
  end
end

-- Clear rendered images from buffer
function M.clear_images(bufnr)
  -- Handle current buffer if bufnr is 0
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  
  -- Get stored images
  local images = vim.b[bufnr].notediscovery_images
  if not images or #images == 0 then
    return
  end
  
  -- Check if image.nvim is available
  local has_image, image_nvim = pcall(require, "image")
  if not has_image then
    vim.b[bufnr].notediscovery_images = nil
    return
  end
  
  -- Clear each image
  for _, image in ipairs(images) do
    pcall(function()
      image:clear()
    end)
  end
  
  -- Clear buffer variable
  vim.b[bufnr].notediscovery_images = nil
end

-- Toggle images on/off
function M.toggle_images(bufnr)
  -- Handle current buffer if bufnr is 0
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  
  -- Check if images are currently rendered
  local images = vim.b[bufnr].notediscovery_images
  if images and #images > 0 then
    -- Images are shown, hide them
    M.clear_images(bufnr)
    notify("Images hidden", vim.log.levels.INFO)
  else
    -- Images are hidden, show them
    local note_path = vim.b[bufnr].notediscovery_path
    if note_path then
      M.render_images(bufnr, note_path)
      notify("Images shown", vim.log.levels.INFO)
    else
      notify("Not a NoteDiscovery buffer", vim.log.levels.WARN)
    end
  end
end

-- Helper function to execute curl commands
local function curl_request(method, endpoint, data, debug, retry_on_auth)
  if retry_on_auth == nil then
    retry_on_auth = true
  end
  
  if not check_config() then
    return nil
  end
  
  local url = M.config.url .. endpoint
  local cmd
  
  if data then
    local json = vim.fn.json_encode(data)
    cmd = string.format(
      'curl -b %s -X %s -H "Content-Type: application/json" -d %s -s -w "\\n%%{http_code}" %s',
      M.config.cookies_file, method, vim.fn.shellescape(json), vim.fn.shellescape(url)
    )
  else
    cmd = string.format('curl -b %s -s -w "\\n%%{http_code}" %s', M.config.cookies_file, vim.fn.shellescape(url))
  end
  
  -- Debug mode: show the command
  if debug or M.config.debug then
    log("Debug: " .. cmd, vim.log.levels.INFO)
  end
  
  local output = vim.fn.system(cmd)
  local curl_exit = vim.v.shell_error
  
  -- Split response body and HTTP code
  local lines = vim.split(output, "\n")
  local http_code = lines[#lines]
  table.remove(lines, #lines)
  local response = table.concat(lines, "\n")
  
  -- Debug: show response
  if debug or M.config.debug then
    log("Debug: HTTP " .. http_code .. ", Response: " .. response:sub(1, 500), vim.log.levels.INFO)
  end
  
  -- Check for curl errors
  if curl_exit ~= 0 then
    vim.notify("✗ Curl failed (exit " .. curl_exit .. "). Check your URL: " .. M.config.url, vim.log.levels.ERROR)
    return nil
  end
  
  -- Check HTTP status codes
  if http_code == "401" then
    -- Auto-login if enabled
    if M.config.auto_login and retry_on_auth then
      notify("Session expired. Attempting auto-login...", vim.log.levels.WARN)
      local login_success = M.login()
      if login_success then
        notify("Retrying request...", vim.log.levels.INFO)
        -- Retry the request once with retry disabled to prevent infinite loop
        return curl_request(method, endpoint, data, debug, false)
      else
        notify("✗ Auto-login failed", vim.log.levels.ERROR)
        return nil
      end
    else
      notify("✗ Not authenticated. Run :NoteLogin first", vim.log.levels.ERROR)
      return nil
    end
  elseif http_code == "404" then
    notify("✗ Not found (404). Check the path or URL", vim.log.levels.ERROR)
    return nil
  elseif http_code:match("^[45]") then
    notify("✗ API error (HTTP " .. http_code .. "): " .. response:sub(1, 100), vim.log.levels.ERROR)
    return nil
  end
  
  -- Try to parse JSON response
  local ok, parsed = pcall(vim.fn.json_decode, response)
  if ok then
    return parsed
  else
    return response
  end
end

-- Login to NoteDiscovery and create session cookie
function M.login()
  if not check_config() then
    return false
  end
  
  -- Ensure data directory exists for cookies file
  vim.fn.mkdir(M.config.data_dir, "p")
  
  -- Extract base URL (remove /api suffix if present)
  local base_url = M.config.url:gsub("/api$", "")
  
  -- Prompt for password with hidden input
  local password = vim.fn.inputsecret("NoteDiscovery password: ")
  
  if password == "" then
    notify("Login cancelled", vim.log.levels.WARN)
    return false
  end
  
  -- Execute login curl command
  local cmd = string.format(
    'curl -L -c %s -X POST -H "Content-Type: application/x-www-form-urlencoded" -d %s -s -w "%%{http_code}" -o /dev/null %s',
    M.config.cookies_file,
    vim.fn.shellescape("password=" .. password),
    vim.fn.shellescape(base_url .. "/login")
  )
  
  local http_code = vim.fn.system(cmd)
  
  if vim.v.shell_error == 0 and (http_code == "303" or http_code == "200") then
    notify("✓ Login successful!", vim.log.levels.INFO)
    return true
  else
    notify("✗ Login failed (HTTP " .. http_code .. "). Check your password.", vim.log.levels.ERROR)
    return false
  end
end

-- Test connection to NoteDiscovery
function M.test_connection()
  if not check_config() then
    return
  end
  
  vim.notify("Testing connection to " .. M.config.url .. "...", vim.log.levels.INFO)
  
  -- Check if cookies file exists
  local cookies_exist = vim.fn.filereadable(M.config.cookies_file) == 1
  if not cookies_exist then
    vim.notify("⚠ No session cookie found. Run :NoteLogin first.", vim.log.levels.WARN)
  end
  
  -- Try to get config endpoint (doesn't require auth)
  local base_url = M.config.url:gsub("/api$", "")
  local cmd = string.format('curl -s -w "\\n%%{http_code}" %s', vim.fn.shellescape(base_url .. "/health"))
  local output = vim.fn.system(cmd)
  local lines = vim.split(output, "\n")
  local http_code = lines[#lines]
  
  if vim.v.shell_error ~= 0 then
    vim.notify("✗ Cannot reach server. Check URL: " .. M.config.url, vim.log.levels.ERROR)
    return
  end
  
  if http_code == "200" then
    vim.notify("✓ Server is reachable!", vim.log.levels.INFO)
    
    -- Now test authenticated endpoint
    local result = curl_request("GET", "/notes")
    if result then
      vim.notify("✓ Authentication OK! Connection fully working.", vim.log.levels.INFO)
    end
  else
    vim.notify("✗ Server returned HTTP " .. http_code, vim.log.levels.ERROR)
  end
end

-- Save current buffer as a note
function M.save_note(note_path)
  if not note_path or note_path == "" then
    note_path = vim.fn.input("Note path: ", "", "file")
  end
  
  if note_path == "" then
    notify("Save cancelled", vim.log.levels.WARN)
    return
  end
  
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local content = table.concat(lines, "\n")
  
  local result = curl_request("POST", "/notes/" .. note_path, { content = content })
  
  if result and result.success then
    notify("✓ Note saved: " .. note_path, vim.log.levels.INFO)
  else
    notify("✗ Failed to save note", vim.log.levels.ERROR)
  end
end

-- Load a note into current buffer
function M.load_note(note_path, debug)
  if not note_path or note_path == "" then
    note_path = vim.fn.input("Note path: ", "", "file")
  end
  
  if note_path == "" then
    notify("Load cancelled", vim.log.levels.WARN)
    return
  end
  
  -- URL encode the note path
  local encoded_path = url_encode(note_path)
  local result = curl_request("GET", "/notes/" .. encoded_path, nil, debug)
  
  if result and result.content then
    -- Ensure we're in a modifiable buffer
    local bufnr = vim.api.nvim_get_current_buf()
    local buftype = vim.api.nvim_buf_get_option(bufnr, 'buftype')
    
    -- If current buffer is special (nofile, etc), create a new buffer
    if buftype ~= '' then
      vim.cmd('enew')
      bufnr = vim.api.nvim_get_current_buf()
    end
    
    -- Make sure buffer is modifiable
    vim.api.nvim_buf_set_option(bufnr, 'modifiable', true)
    
    local lines = vim.split(result.content, "\n")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(bufnr, 'filetype', 'markdown')
    
    -- Store the note path for saving with :w/:wq
    vim.b[bufnr].notediscovery_path = note_path
    
    -- Set up buffer name for display
    vim.api.nvim_buf_set_name(bufnr, 'notediscovery://' .. note_path)
    
    -- Disable swap file to prevent conflicts
    vim.api.nvim_buf_set_option(bufnr, 'swapfile', false)
    vim.api.nvim_buf_set_option(bufnr, 'buftype', 'acwrite')
    vim.api.nvim_buf_set_option(bufnr, 'bufhidden', 'hide')
    
    -- Intercept write commands to save to NoteDiscovery
    vim.api.nvim_create_autocmd("BufWriteCmd", {
      buffer = bufnr,
      callback = function()
        local content_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local content = table.concat(content_lines, "\n")
        
        local save_result = curl_request("POST", "/notes/" .. url_encode(note_path), { content = content })
        
        if save_result and save_result.success then
          vim.api.nvim_buf_set_option(bufnr, 'modified', false)
          vim.notify("✓ Note saved: " .. note_path, vim.log.levels.INFO)
        else
          vim.notify("✗ Failed to save note", vim.log.levels.ERROR)
        end
      end,
    })
    
    -- Clean up images when buffer is closed
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = bufnr,
      callback = function()
        M.clear_images(bufnr)
      end,
    })
    
    -- Mark buffer as not modified initially
    vim.api.nvim_buf_set_option(bufnr, 'modified', false)
    
    -- Render images if enabled
    if M.config.auto_render_images then
      vim.schedule(function()
        M.render_images(bufnr, note_path)
      end)
    end
    
    -- Store last loaded note for quick reload
    last_loaded_note = note_path
    save_last_note(note_path)
    
    notify("✓ Note loaded: " .. note_path, vim.log.levels.INFO)
  else
    notify("✗ Note not found or failed to load", vim.log.levels.ERROR)
  end
end

-- Load the last loaded note
function M.load_last_note()
  if not last_loaded_note then
    notify("No previously loaded note", vim.log.levels.WARN)
    return
  end
  
  M.load_note(last_loaded_note)
end

-- Create a new note from template
function M.new_note(note_path)
  if not note_path or note_path == "" then
    note_path = vim.fn.input("New note path: ", "", "file")
  end
  
  if note_path == "" then
    notify("Cancelled", vim.log.levels.WARN)
    return
  end
  
  -- Create buffer with basic template
  vim.cmd('enew')
  local bufnr = vim.api.nvim_get_current_buf()
  
  local template = {
    "# " .. vim.fn.fnamemodify(note_path, ":t:r"),
    "",
    os.date("%Y-%m-%d"),
    "",
    "",
  }
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, template)
  vim.api.nvim_buf_set_option(bufnr, 'filetype', 'markdown')
  
  -- Store the path for easy saving
  vim.b[bufnr].notediscovery_path = note_path
  
  -- Set up buffer name for display
  vim.api.nvim_buf_set_name(bufnr, 'notediscovery://' .. note_path)
  
  -- Disable swap file to prevent conflicts
  vim.api.nvim_buf_set_option(bufnr, 'swapfile', false)
  vim.api.nvim_buf_set_option(bufnr, 'buftype', 'acwrite')
  vim.api.nvim_buf_set_option(bufnr, 'bufhidden', 'hide')
  
  -- Intercept write commands to save to NoteDiscovery
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = bufnr,
    callback = function()
      local content_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local content = table.concat(content_lines, "\n")
      
      local result = curl_request("POST", "/notes/" .. url_encode(note_path), { content = content })
      
      if result and result.success then
        vim.api.nvim_buf_set_option(bufnr, 'modified', false)
        vim.notify("✓ Note saved: " .. note_path, vim.log.levels.INFO)
      else
        vim.notify("✗ Failed to save note", vim.log.levels.ERROR)
      end
    end,
  })
  
  -- Clean up images when buffer is closed
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    callback = function()
      M.clear_images(bufnr)
    end,
  })
  
  notify("New note: " .. note_path, vim.log.levels.INFO)
end

-- Search notes
function M.search_notes(query, debug)
  if not query or query == "" then
    query = vim.fn.input("Search notes: ")
  end
  
  if query == "" then
    notify("Search cancelled", vim.log.levels.WARN)
    return
  end
  
  local result = curl_request("GET", "/search?q=" .. url_encode(query), nil, debug)
  
  if not result then
    vim.notify("✗ Search failed - API request error", vim.log.levels.ERROR)
    return
  end
  
  if debug then
    vim.notify("Debug: Full response: " .. vim.inspect(result), vim.log.levels.INFO)
  end
  
  if result.results then
    if #result.results == 0 then
      vim.notify("✓ No notes found matching: " .. query, vim.log.levels.INFO)
      return
    end
    
    -- Create a new buffer with search results
    vim.cmd('new')
    local bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_option(bufnr, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(bufnr, 'bufhidden', 'wipe')
    vim.api.nvim_buf_set_name(bufnr, 'NoteDiscovery Search: ' .. query)
    
    local lines = {
      "Search results for: " .. query,
      "Found " .. #result.results .. " note(s)",
      "Press <Enter> to load note under cursor, q to quit",
      string.rep("─", 60),
      ""
    }
    
    -- Store note paths by line number
    local line_to_path = {}
    
    for _, note in ipairs(result.results) do
      table.insert(lines, "📄 " .. note.path)
      line_to_path[#lines] = note.path
      
      if note.folder and note.folder ~= "" then
        table.insert(lines, "   📁 " .. note.folder)
      end
      if note.snippet then
        local snippet = note.snippet:gsub("\n", " ")
        table.insert(lines, "   " .. snippet)
      end
      table.insert(lines, "")
    end
    
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
    
    -- Set up keybindings for this buffer (using closure to capture line_to_path)
    vim.keymap.set('n', '<CR>', function()
      local line = vim.fn.line('.')
      if line_to_path[line] then
        vim.cmd('close')
        M.load_note(line_to_path[line])
      end
    end, { buffer = bufnr, desc = 'Load note' })
    
    vim.keymap.set('n', 'q', ':close<CR>', { buffer = bufnr, desc = 'Close' })
    
    vim.notify("✓ Found " .. #result.results .. " note(s)", vim.log.levels.INFO)
  else
    vim.notify("✗ Unexpected API response format. Expected 'results' field. " .. (debug and vim.inspect(result) or "Use :NoteSearchDebug to see full response"), vim.log.levels.ERROR)
  end
end

-- List all notes
function M.list_notes()
  local result = curl_request("GET", "/notes")
  
  if result and result.notes then
    vim.cmd('new')
    local bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_option(bufnr, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(bufnr, 'bufhidden', 'wipe')
    vim.api.nvim_buf_set_name(bufnr, 'NoteDiscovery - All Notes')
    
    local lines = {
      "All Notes (" .. #result.notes .. " total)",
      "Press <Enter> to load note under cursor, q to quit",
      string.rep("─", 60),
      ""
    }
    
    -- Store note paths by line number for easy lookup
    local line_to_path = {}
    
    -- Group by folder
    local by_folder = {}
    for _, note in ipairs(result.notes) do
      local folder = note.folder or "/"
      if not by_folder[folder] then
        by_folder[folder] = {}
      end
      table.insert(by_folder[folder], note)
    end
    
    -- Sort folders
    local folders = {}
    for folder, _ in pairs(by_folder) do
      table.insert(folders, folder)
    end
    table.sort(folders)
    
    for _, folder in ipairs(folders) do
      table.insert(lines, "📁 " .. folder)
      for _, note in ipairs(by_folder[folder]) do
        table.insert(lines, "  📄 " .. note.name)
        -- Store the full path for this line
        line_to_path[#lines] = note.path
      end
      table.insert(lines, "")
    end
    
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
    
    -- Set up keybindings for this buffer (using closure to capture line_to_path)
    vim.keymap.set('n', '<CR>', function()
      local line = vim.fn.line('.')
      if line_to_path[line] then
        vim.cmd('close')
        M.load_note(line_to_path[line])
      end
    end, { buffer = bufnr, desc = 'Load note' })
    
    vim.keymap.set('n', 'q', ':close<CR>', { buffer = bufnr, desc = 'Close' })
    
    vim.notify("✓ Listed " .. #result.notes .. " note(s)", vim.log.levels.INFO)
  else
    vim.notify("✗ Failed to list notes", vim.log.levels.ERROR)
  end
end

-- Create quick note from yanked text or current selection
function M.quick_note()
  local content = vim.fn.getreg('"')
  
  if content == "" then
    vim.notify("No content in register", vim.log.levels.WARN)
    return
  end
  
  local timestamp = os.date(M.config.quick_note_format)
  local note_path = M.config.default_folder .. "/" .. timestamp
  
  local result = curl_request("POST", "/notes/" .. note_path, { content = content })
  
  if result and result.success then
    vim.notify("✓ Quick note created: " .. note_path, vim.log.levels.INFO)
  else
    vim.notify("✗ Failed to create quick note", vim.log.levels.ERROR)
  end
end

-- Delete current note
function M.delete_note(note_path)
  if not check_config() then
    return
  end
  
  if not note_path or note_path == "" then
    note_path = vim.fn.input("Note path to delete: ", "", "file")
  end
  
  if note_path == "" then
    vim.notify("Delete cancelled", vim.log.levels.WARN)
    return
  end
  
  local confirm = vim.fn.input("Delete '" .. note_path .. "'? (yes/no): ")
  if confirm:lower() ~= "yes" then
    vim.notify("Delete cancelled", vim.log.levels.INFO)
    return
  end
  
  local cmd = string.format('curl -b %s -X DELETE -s %s', 
    M.config.cookies_file, vim.fn.shellescape(M.config.url .. "/notes/" .. note_path))
  vim.fn.system(cmd)
  
  if vim.v.shell_error == 0 then
    vim.notify("✓ Note deleted: " .. note_path, vim.log.levels.INFO)
  else
    vim.notify("✗ Failed to delete note", vim.log.levels.ERROR)
  end
end

-- View debug log
function M.view_log()
  if vim.fn.filereadable(M.config.log_file) == 0 then
    vim.notify("Log file not found: " .. M.config.log_file, vim.log.levels.WARN)
    return
  end
  
  vim.cmd('new ' .. vim.fn.fnameescape(M.config.log_file))
  vim.cmd('setlocal buftype=nowrite')
  vim.cmd('normal! G') -- Jump to end
end

-- Clear debug log
function M.clear_log()
  local file = io.open(M.config.log_file, "w")
  if file then
    file:close()
    vim.notify("✓ Log cleared: " .. M.config.log_file, vim.log.levels.INFO)
  else
    vim.notify("✗ Failed to clear log", vim.log.levels.ERROR)
  end
end

-- Optional: Set up keybindings (uncomment and customize as needed)
-- vim.keymap.set('n', '<leader>ns', ':NoteSave<CR>', { desc = 'NoteDiscovery: Save note' })
-- vim.keymap.set('n', '<leader>nl', ':NoteLoad<CR>', { desc = 'NoteDiscovery: Load note' })
-- vim.keymap.set('n', '<leader>nn', ':NoteNew<CR>', { desc = 'NoteDiscovery: New note' })
-- vim.keymap.set('n', '<leader>nf', ':NoteSearch<CR>', { desc = 'NoteDiscovery: Search notes' })
-- vim.keymap.set('n', '<leader>na', ':NoteList<CR>', { desc = 'NoteDiscovery: List all notes' })
-- vim.keymap.set('v', '<leader>nq', '"+y:NoteQuick<CR>', { desc = 'NoteDiscovery: Quick note from selection' })

return M
