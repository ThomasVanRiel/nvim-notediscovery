" plugin/notediscovery.vim
" NoteDiscovery integration for Neovim

if !has('nvim')
  finish
endif

if exists('g:loaded_notediscovery')
  finish
endif
let g:loaded_notediscovery = 1

" Register commands
command! -nargs=0 NoteLogin lua require('notediscovery').login()
command! -nargs=? -complete=file NoteSave lua require('notediscovery').save_note(<q-args>)
command! -nargs=? -complete=file NoteLoad lua require('notediscovery').load_note(<q-args>)
command! -nargs=0 NoteLoadLast lua require('notediscovery').load_last_note()
command! -nargs=? -complete=file NoteNew lua require('notediscovery').new_note(<q-args>)
command! -nargs=? NoteSearch lua require('notediscovery').search_notes(<q-args>)
command! -nargs=0 NoteList lua require('notediscovery').list_notes()
command! -nargs=0 NoteQuick lua require('notediscovery').quick_note()
command! -nargs=? -complete=file NoteDelete lua require('notediscovery').delete_note(<q-args>)
command! -nargs=0 NoteImagesShow lua require('notediscovery').render_images(0, vim.b.notediscovery_path)
command! -nargs=0 NoteImagesHide lua require('notediscovery').clear_images(0)
command! -nargs=0 NoteImagesToggle lua require('notediscovery').toggle_images(0)
