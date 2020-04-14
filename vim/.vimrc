if empty(glob('~/.vim/autoload/plug.vim'))
  silent !curl -fLo ~/.vim/autoload/plug.vim --create-dirs
    \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  autocmd VimEnter * PlugInstall | source $MYVIMRC
endif

call plug#begin('~/.vim/plugged')
Plug 'arcticicestudio/nord-vim'
Plug 'airblade/vim-gitgutter'
Plug 'Yggdroot/indentLine'
Plug 'itchyny/lightline.vim'
Plug 'tpope/vim-fugitive'
call plug#end()

"+--- Yggdroot/indentLine ---+
let g:indentLine_enabled = 0
let g:indentLine_char = '│'

"+--- itchyny/lightline.vim ---+
let g:lightline = {
      \ 'colorscheme': 'nord',
      \ 'active': {
      \   'left': [
      \     [ 'mode', 'paste' ],
      \     [ 'fugitive', 'filename' ]
      \   ]
      \ },
      \ 'component_function': {
      \   'fugitive': 'LightlineFugitive',
      \   'readonly': 'LightlineReadonly',
      \   'modified': 'LightlineModified',
      \   'filename': 'LightlineFilename'
      \ },
      \ 'separator': {
      \   'left': '',
      \   'right': ''
      \ },
      \ 'subseparator': {
      \   'left': '',
      \   'right': ''
      \ }
    \ }

function! LightlineModified()
  if &filetype == "help"
    return ""
  elseif &modified
    return "+"
  elseif &modifiable
    return ""
  else
    return ""
  endif
endfunction

function! LightlineReadonly()
  if &filetype == "help"
    return ""
  elseif &readonly
    return ""
  else
    return ""
  endif
endfunction

function! LightlineFugitive()
"  if exists("*fugitive#head")
    let branch = fugitive#head()
    return branch !=# '' ? ' '.branch : ''
"  endif
  return ''
endfunction

function! LightlineFilename()
  return ('' != LightlineReadonly() ? LightlineReadonly() . ' ' : '') .
       \ ('' != expand('%:t') ? expand('%:t') : '[No Name]') .
       \ ('' != LightlineModified() ? ' ' . LightlineModified() : '')
endfunction

"+--- airblade/vim-gitgutter ---+
let g:gitgutter_realtime = 1
let g:gitgutter_eager = 1

"+---------------+
"+ Auto Commands +
"+---------------+
" Enable syntax highlight syncing from start
augroup vimrc-sync-fromstart
  autocmd!
  autocmd BufEnter * :syntax sync fromstart
augroup END

"+---------------+
"+ Configuration +
"+---------------+
syntax enable
colorscheme nord

filetype plugin on
filetype indent on
set pastetoggle=<F3>
set autochdir
set binary
set nobackup
set nocompatible
set noswapfile
set nowb
set encoding=utf-8
set fileencoding=utf-8
set fileencodings=utf-8
set ttyfast
set viminfo=
set updatetime=250

"if has("gui_running")
  set mouse=a
"endif

"+----+
"+ UI +
"+----+
set ffs=unix,dos,mac
set gfn=Source\ Code\ Pro\ Regular\ 12
set guioptions-=m
set guioptions-=T
set guioptions-=r
set guioptions-=L
set termguicolors
set hidden
set laststatus=2
set lazyredraw
set noerrorbells
set noshowmode
set novisualbell
set number
set ruler
set t_vb=
set tm=500
set wildmenu
set wildignore=*~,*.pyc
set wildignore+=*/.git/*,*/.hg/*,*/.svn/*

set shortmess=F

"+--- Editor ---+
set autoindent
set backspace=indent,eol,start
set cursorline
set colorcolumn=160
set expandtab
set foldcolumn=1
set foldenable
set foldlevelstart=10
set guicursor=a:ver25-Cursor/lCursor
set linebreak
set listchars=eol:¬,space:·,tab:»\
set magic
set mat=2
set shiftwidth=2
set showmatch

" Toggle the sign column automatically when there are signs available to display.
set signcolumn=auto
set smartindent
set smarttab
set softtabstop=2
set tabstop=2
set textwidth=160

" Automatically wrap left and right.
" This allows to move the cursor to the previous/next line after reaching first/last character in the line using the arrow keys in normal-, insert- (<,>) and visual mode ([,]) or the h and l keys.
set whichwrap+=<,>,h,l,[,]
set wrap

"+--- Search ---+
set ignorecase
set smartcase
set hlsearch
set incsearch
