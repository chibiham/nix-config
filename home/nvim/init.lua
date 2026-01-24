-- リーダーキー設定
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- 基本設定読み込み
require("config.options")
require("config.keymaps")
require("config.lazy-bootstrap")
