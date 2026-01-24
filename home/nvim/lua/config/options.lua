local opt = vim.opt

-- UI
opt.number = true
opt.relativenumber = true
opt.signcolumn = "yes"
opt.cursorline = true
opt.termguicolors = true
opt.showmode = false
opt.wrap = false
opt.scrolloff = 8
opt.sidescrolloff = 8

-- 検索
opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = true
opt.incsearch = true

-- インデント
opt.tabstop = 2
opt.softtabstop = 2
opt.shiftwidth = 2
opt.expandtab = true
opt.smartindent = true
opt.breakindent = true

-- 編集
opt.undofile = true
opt.backup = false
opt.swapfile = false
opt.mouse = "a"
opt.clipboard = "unnamedplus"
opt.completeopt = "menu,menuone,noselect"

-- 分割
opt.splitright = true
opt.splitbelow = true

-- パフォーマンス
opt.updatetime = 250
opt.timeoutlen = 300

-- エンコーディング
opt.encoding = "utf-8"
opt.fileencoding = "utf-8"
