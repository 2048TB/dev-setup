-- Neovim 配置 - Catppuccin Mocha 主题
-- 配置位置: ~/.config/nvim/init.lua
-- 现代化、简洁的 Neovim 配置

-- ===== 基础设置 =====

-- 行号
vim.opt.number = true          -- 显示行号
vim.opt.relativenumber = true  -- 相对行号

-- 缩进
vim.opt.expandtab = true       -- 使用空格替代 Tab
vim.opt.shiftwidth = 2         -- 自动缩进宽度
vim.opt.tabstop = 2            -- Tab 宽度
vim.opt.softtabstop = 2        -- 软 Tab 宽度
vim.opt.smartindent = true     -- 智能缩进

-- 搜索
vim.opt.ignorecase = true      -- 忽略大小写
vim.opt.smartcase = true       -- 智能大小写（输入大写时精确匹配）
vim.opt.hlsearch = true        -- 高亮搜索结果
vim.opt.incsearch = true       -- 增量搜索

-- 界面
vim.opt.termguicolors = true   -- 真彩色支持
vim.opt.cursorline = true      -- 高亮当前行
vim.opt.signcolumn = "yes"     -- 始终显示符号列
vim.opt.scrolloff = 8          -- 光标上下保留 8 行
vim.opt.sidescrolloff = 8      -- 光标左右保留 8 列
vim.opt.wrap = false           -- 不自动换行

-- 编辑体验
vim.opt.mouse = "a"            -- 启用鼠标
vim.opt.clipboard = "unnamedplus"  -- 系统剪贴板
vim.opt.splitright = true      -- 垂直分割到右侧
vim.opt.splitbelow = true      -- 水平分割到下方
vim.opt.swapfile = false       -- 禁用交换文件
vim.opt.backup = false         -- 禁用备份文件
vim.opt.undofile = true        -- 持久化撤销

-- 性能
vim.opt.updatetime = 300       -- 更新时间（毫秒）
vim.opt.timeoutlen = 500       -- 快捷键等待时间

-- 编码
vim.opt.encoding = "utf-8"
vim.opt.fileencoding = "utf-8"

-- ===== Leader 键设置 =====
vim.g.mapleader = " "          -- Leader 键设为空格

-- ===== 快捷键映射 =====

local keymap = vim.keymap.set

-- 正常模式

-- 保存和退出
keymap("n", "<leader>w", ":w<CR>", { desc = "保存文件" })
keymap("n", "<leader>q", ":q<CR>", { desc = "退出" })
keymap("n", "<leader>Q", ":qa!<CR>", { desc = "强制退出所有" })

-- 分屏导航（Vim 风格）
keymap("n", "<C-h>", "<C-w>h", { desc = "移动到左侧窗口" })
keymap("n", "<C-j>", "<C-w>j", { desc = "移动到下方窗口" })
keymap("n", "<C-k>", "<C-w>k", { desc = "移动到上方窗口" })
keymap("n", "<C-l>", "<C-w>l", { desc = "移动到右侧窗口" })

-- 分屏大小调整
keymap("n", "<C-Up>", ":resize +2<CR>", { desc = "增加窗口高度" })
keymap("n", "<C-Down>", ":resize -2<CR>", { desc = "减少窗口高度" })
keymap("n", "<C-Left>", ":vertical resize -2<CR>", { desc = "减少窗口宽度" })
keymap("n", "<C-Right>", ":vertical resize +2<CR>", { desc = "增加窗口宽度" })

-- 清除搜索高亮
keymap("n", "<Esc>", ":noh<CR>", { desc = "清除搜索高亮" })

-- 可视模式

-- 缩进后保持选择
keymap("v", "<", "<gv", { desc = "向左缩进" })
keymap("v", ">", ">gv", { desc = "向右缩进" })

-- 移动选中的行
keymap("v", "J", ":m '>+1<CR>gv=gv", { desc = "向下移动行" })
keymap("v", "K", ":m '<-2<CR>gv=gv", { desc = "向上移动行" })

-- ===== 插件管理器 - Lazy.nvim =====

-- 自动安装 lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- ===== 插件配置 =====

require("lazy").setup({
  -- Catppuccin 主题
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    config = function()
      require("catppuccin").setup({
        flavour = "mocha", -- latte, frappe, macchiato, mocha
        transparent_background = false,
        show_end_of_buffer = false,
        term_colors = true,
        dim_inactive = {
          enabled = false,
          shade = "dark",
          percentage = 0.15,
        },
        no_italic = false,
        no_bold = false,
        styles = {
          comments = { "italic" },
          conditionals = { "italic" },
        },
        integrations = {
          cmp = true,
          gitsigns = true,
          nvimtree = true,
          telescope = true,
          treesitter = true,
        },
      })
      vim.cmd.colorscheme("catppuccin")
    end,
  },

  -- 文件浏览器
  {
    "nvim-tree/nvim-tree.lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("nvim-tree").setup({
        view = {
          width = 30,
        },
      })
      keymap("n", "<leader>e", ":NvimTreeToggle<CR>", { desc = "切换文件树" })
    end,
  },

  -- 状态栏
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("lualine").setup({
        options = {
          theme = "catppuccin",
          component_separators = { left = "", right = "" },
          section_separators = { left = "", right = "" },
        },
      })
    end,
  },

  -- 模糊查找
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      local builtin = require("telescope.builtin")
      keymap("n", "<leader>ff", builtin.find_files, { desc = "查找文件" })
      keymap("n", "<leader>fg", builtin.live_grep, { desc = "全局搜索" })
      keymap("n", "<leader>fb", builtin.buffers, { desc = "切换缓冲区" })
    end,
  },

  -- 语法高亮
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter.configs").setup({
        ensure_installed = { "lua", "vim", "vimdoc", "python", "javascript", "typescript", "rust", "go" },
        highlight = {
          enable = true,
        },
        indent = {
          enable = true,
        },
      })
    end,
  },

  -- Git 集成
  {
    "lewis6991/gitsigns.nvim",
    config = function()
      require("gitsigns").setup()
    end,
  },

  -- 自动补全
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "L3MON4D3/LuaSnip",
    },
    config = function()
      local cmp = require("cmp")
      cmp.setup({
        snippet = {
          expand = function(args)
            require("luasnip").lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-b>"] = cmp.mapping.scroll_docs(-4),
          ["<C-f>"] = cmp.mapping.scroll_docs(4),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-e>"] = cmp.mapping.abort(),
          ["<CR>"] = cmp.mapping.confirm({ select = true }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
          { name = "buffer" },
          { name = "path" },
        }),
      })
    end,
  },

  -- 注释插件
  {
    "numToStr/Comment.nvim",
    config = function()
      require("Comment").setup()
    end,
  },

  -- 自动配对括号
  {
    "windwp/nvim-autopairs",
    config = function()
      require("nvim-autopairs").setup()
    end,
  },

  -- 缩进指示线
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    config = function()
      require("ibl").setup()
    end,
  },

  -- LSP 配置
  {
    "williamboman/mason.nvim",
    config = function()
      require("mason").setup()
    end,
  },

  {
    "williamboman/mason-lspconfig.nvim",
    dependencies = { "williamboman/mason.nvim" },
    config = function()
      require("mason-lspconfig").setup({
        ensure_installed = {
          "lua_ls",      -- Lua
          "pyright",     -- Python
          "tsserver",    -- TypeScript/JavaScript
          "rust_analyzer", -- Rust
          "gopls",       -- Go
        },
        automatic_installation = true,
      })
    end,
  },

  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "williamboman/mason.nvim",
      "williamboman/mason-lspconfig.nvim",
      "hrsh7th/cmp-nvim-lsp",
    },
    config = function()
      local lspconfig = require("lspconfig")
      local capabilities = require("cmp_nvim_lsp").default_capabilities()

      -- 通用 LSP 快捷键
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local opts = { buffer = args.buf }
          keymap("n", "gd", vim.lsp.buf.definition, opts)
          keymap("n", "K", vim.lsp.buf.hover, opts)
          keymap("n", "<leader>rn", vim.lsp.buf.rename, opts)
          keymap("n", "<leader>ca", vim.lsp.buf.code_action, opts)
          keymap("n", "gr", vim.lsp.buf.references, opts)
          keymap("n", "<leader>f", function()
            vim.lsp.buf.format({ async = true })
          end, opts)
        end,
      })

      -- 配置各语言 LSP
      local servers = {
        "lua_ls",
        "pyright",
        "tsserver",
        "rust_analyzer",
        "gopls",
      }

      for _, server in ipairs(servers) do
        lspconfig[server].setup({
          capabilities = capabilities,
        })
      end

      -- Lua 特殊配置
      lspconfig.lua_ls.setup({
        capabilities = capabilities,
        settings = {
          Lua = {
            diagnostics = {
              globals = { "vim" },
            },
          },
        },
      })
    end,
  },
})

-- ===== 自动命令 =====

-- 高亮复制的文本
vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function()
    vim.highlight.on_yank({ timeout = 200 })
  end,
})

-- 保存时自动格式化（可选）
-- vim.api.nvim_create_autocmd("BufWritePre", {
--   callback = function()
--     vim.lsp.buf.format()
--   end,
-- })
