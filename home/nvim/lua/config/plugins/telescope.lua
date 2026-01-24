return {
  {
    "nvim-telescope/telescope.nvim",
    cmd = "Telescope",
    dependencies = {
      "nvim-lua/plenary.nvim",
      { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
    },
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "ファイル検索" },
      { "<leader>fg", "<cmd>Telescope live_grep<cr>", desc = "文字列検索" },
      { "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "バッファ" },
      { "<leader>fh", "<cmd>Telescope help_tags<cr>", desc = "ヘルプ" },
      { "<leader>fr", "<cmd>Telescope oldfiles<cr>", desc = "最近使ったファイル" },
    },
    config = function()
      local telescope = require("telescope")
      telescope.setup({
        defaults = {
          prompt_prefix = " ",
          selection_caret = " ",
          path_display = { "smart" },
          file_ignore_patterns = {
            "node_modules", ".git/", "dist/", "build/", "target/",
          },
        },
        pickers = {
          find_files = { hidden = true },
        },
      })
      telescope.load_extension("fzf")
    end,
  },
}
