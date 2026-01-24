return {
  {
    "neovim/nvim-lspconfig",
    version = "v1.0.0",  -- 安定版を使用（deprecation warning回避）
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "folke/neodev.nvim",
    },
    config = function()
      require("neodev").setup({})

      local lspconfig = require("lspconfig")
      local capabilities = require("cmp_nvim_lsp").default_capabilities()

      -- 診断設定
      vim.diagnostic.config({
        virtual_text = true,
        signs = true,
        update_in_insert = false,
        underline = true,
        severity_sort = true,
        float = { border = "rounded", source = "always" },
      })

      -- 診断シンボル
      local signs = { Error = " ", Warn = " ", Hint = "󰠠 ", Info = " " }
      for type, icon in pairs(signs) do
        vim.fn.sign_define("DiagnosticSign" .. type, { text = icon, texthl = "DiagnosticSign" .. type })
      end

      -- LSPキーマップ
      local on_attach = function(client, bufnr)
        local opts = { buffer = bufnr }
        vim.keymap.set("n", "gd", vim.lsp.buf.definition, vim.tbl_extend("force", opts, { desc = "定義へ移動" }))
        vim.keymap.set("n", "gr", vim.lsp.buf.references, vim.tbl_extend("force", opts, { desc = "参照表示" }))
        vim.keymap.set("n", "K", vim.lsp.buf.hover, vim.tbl_extend("force", opts, { desc = "ホバードキュメント" }))
        vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, vim.tbl_extend("force", opts, { desc = "リネーム" }))
        vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, vim.tbl_extend("force", opts, { desc = "コードアクション" }))
        vim.keymap.set("n", "<leader>f", function() vim.lsp.buf.format({ async = true }) end, vim.tbl_extend("force", opts, { desc = "フォーマット" }))
        vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, vim.tbl_extend("force", opts, { desc = "前の診断" }))
        vim.keymap.set("n", "]d", vim.diagnostic.goto_next, vim.tbl_extend("force", opts, { desc = "次の診断" }))
      end

      local default_config = {
        on_attach = on_attach,
        capabilities = capabilities,
      }

      -- 各言語のLSP設定
      lspconfig.ts_ls.setup(default_config)
      lspconfig.nil_ls.setup(default_config)
      lspconfig.lua_ls.setup(vim.tbl_extend("force", default_config, {
        settings = {
          Lua = {
            diagnostics = { globals = { "vim" } },
            workspace = { library = vim.api.nvim_get_runtime_file("", true), checkThirdParty = false },
            telemetry = { enable = false },
          },
        },
      }))
      lspconfig.pyright.setup(default_config)
      lspconfig.gopls.setup(default_config)
      lspconfig.rust_analyzer.setup(default_config)
      lspconfig.jsonls.setup(default_config)
      lspconfig.yamlls.setup(default_config)
      lspconfig.marksman.setup(default_config)
    end,
  },
}
