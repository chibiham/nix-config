local keymap = vim.keymap

-- ウィンドウナビゲーション
keymap.set("n", "<C-h>", "<C-w>h", { desc = "左のウィンドウ" })
keymap.set("n", "<C-j>", "<C-w>j", { desc = "下のウィンドウ" })
keymap.set("n", "<C-k>", "<C-w>k", { desc = "上のウィンドウ" })
keymap.set("n", "<C-l>", "<C-w>l", { desc = "右のウィンドウ" })

-- インデント
keymap.set("v", "<", "<gv", { desc = "左インデント（選択保持）" })
keymap.set("v", ">", ">gv", { desc = "右インデント（選択保持）" })

-- 行移動
keymap.set("n", "<A-j>", ":m .+1<CR>==", { desc = "行を下に移動" })
keymap.set("n", "<A-k>", ":m .-2<CR>==", { desc = "行を上に移動" })

-- 検索ハイライト解除
keymap.set("n", "<Esc>", ":noh<CR>", { desc = "検索ハイライト解除" })

-- ペースト改善
keymap.set("v", "p", '"_dP', { desc = "ヤンクせずペースト" })

-- 保存・終了
keymap.set("n", "<leader>w", ":w<CR>", { desc = "保存" })
keymap.set("n", "<leader>q", ":q<CR>", { desc = "終了" })

-- バッファナビゲーション
keymap.set("n", "<S-h>", ":bprevious<CR>", { desc = "前のバッファ" })
keymap.set("n", "<S-l>", ":bnext<CR>", { desc = "次のバッファ" })
keymap.set("n", "<leader>bd", ":bdelete<CR>", { desc = "バッファ削除" })
