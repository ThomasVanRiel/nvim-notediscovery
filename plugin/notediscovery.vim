" plugin/notediscovery.vim
" NoteDiscovery integration for Neovim

" Prevent loading the plugin twice
if exists('g:loaded_notediscovery')
  finish
endif
let g:loaded_notediscovery = 1

" Commands are automatically loaded from lua/notediscovery/init.lua
" when require('notediscovery') is called
