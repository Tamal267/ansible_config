" --- Filetype & Syntax Core ---
filetype plugin indent on   " Enable filetype detection, filetype plugins, and indents
syntax on                   " Enable syntax highlighting

" --- Tab, Indentation & Formatting ---
set tabstop=2               " ts: Render tabs as 2 spaces
set softtabstop=2           " Number of spaces a TAB counts for while editing
set shiftwidth=2            " sw: Formatting/Indentation step size is 2 spaces
set expandtab               " Force Vim to use spaces instead of literal tab characters
set autoindent              " ai: Copy indentation from previous line on newline
set smartindent             " Smart auto-indenting for code blocks

" --- Interface & Behavior Settings ---
set number                  " nu: Show line numbers
set ruler                   " ru: Show cursor position (row, col) in status line
set laststatus=2            " ls=2: Always show the status line
set showmode                " smd: Show current mode (INSERT, VISUAL, etc.)
set showcmd                 " sc: Show incomplete commands in status bar
set scrolloff=3             " so=3: Keep 3 lines visible above/below cursor when scrolling
set mouse=a                 " mouse=a: Enable full mouse support in all modes
set backspace=2             " bs=2: Allow backspacing over everything (indent, eol, start)
set linebreak               " lbr: Wrap long lines at clean visual boundaries (words)
set nocompatible            " nocp: Use modern Vim behaviors over ancient Vi defaults

" --- Search Settings ---
set hlsearch                " hls: Highlight all search matches
set incsearch               " is: Highlight search matches on the fly while typing
set ignorecase              " ic: Ignore case when searching...
set smartcase               " scs: ...unless search query contains uppercase letters

" --- Run code directly from vim with F5 key ---
autocmd FileType python nnoremap <F5> :w<CR>:!python3 %<CR>
autocmd FileType cpp nnoremap <F5> :w<CR>:!g++ -O2 -Wall % -o %:r && ./%:r<CR>
autocmd FileType c nnoremap <F5> :w<CR>:!gcc -O2 -Wall % -o %:r && ./%:r<CR>
autocmd FileType java nnoremap <F5> :w<CR>:!javac % && java %:r<CR>
