return {
  {
    "goolord/alpha-nvim",
    event = "VimEnter",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      local alpha = require("alpha")
      local dashboard = require("alpha.themes.dashboard")

      -- ヘッダー
      dashboard.section.header.val = {
        "                                                     ",
        "  ███╗   ██╗███████╗ ██████╗ ██╗   ██╗██╗███╗   ███╗ ",
        "  ████╗  ██║██╔════╝██╔═══██╗██║   ██║██║████╗ ████║ ",
        "  ██╔██╗ ██║█████╗  ██║   ██║██║   ██║██║██╔████╔██║ ",
        "  ██║╚██╗██║██╔══╝  ██║   ██║╚██╗ ██╔╝██║██║╚██╔╝██║ ",
        "  ██║ ╚████║███████╗╚██████╔╝ ╚████╔╝ ██║██║ ╚═╝ ██║ ",
        "  ╚═╝  ╚═══╝╚══════╝ ╚═════╝   ╚═══╝  ╚═╝╚═╝     ╚═╝ ",
        "                                                     ",
      }

      -- ボタン
      dashboard.section.buttons.val = {
        dashboard.button("f", "  ファイル検索", ":Telescope find_files<CR>"),
        dashboard.button("r", "  最近使ったファイル", ":Telescope oldfiles<CR>"),
        dashboard.button("g", "  文字列検索", ":Telescope live_grep<CR>"),
        dashboard.button("e", "  新規ファイル", ":ene <BAR> startinsert<CR>"),
        dashboard.button("c", "  設定", ":e ~/.config/nvim/init.lua<CR>"),
        dashboard.button("q", "  終了", ":qa<CR>"),
      }

      -- フッター
      local function footer()
        local total_plugins = #vim.tbl_keys(require("lazy").plugins())
        return "   " .. total_plugins .. " plugins loaded"
      end

      dashboard.section.footer.val = footer()

      -- レイアウト
      dashboard.config.layout = {
        { type = "padding", val = 2 },
        dashboard.section.header,
        { type = "padding", val = 2 },
        dashboard.section.buttons,
        { type = "padding", val = 1 },
        dashboard.section.footer,
      }

      alpha.setup(dashboard.config)

      -- Neo-treeを開いているときにalphaを無効化
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "neo-tree",
        callback = function()
          vim.b.alpha_disable = true
        end,
      })
    end,
  },
}
