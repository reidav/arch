require("nvim-treesitter.configs").setup({
  rainbow = {
    enable = true,
    extended_mode = true, -- Also highlight non-bracket delimiters like html tags, boolean or table: lang -> boolean
    max_file_lines = nil, -- Do not enable for files with more than n lines, int
  },
  incremental_selection = {
    enable = true,
    keymaps = {
      init_selection = "<CR>",
      scope_incremental = "<CR>",
      node_incremental = "<CR>",
      node_decremental = "<TAB>",
    },
  },
})
-- Setup treesitter
local ts = require("nvim-treesitter.configs")
local languages = {
  "lua",
  "c",
  "go",
  "rust",
  "bash",
  "css",
  "cpp",
  "c_sharp",
  "fish",
  "graphql",
  "html",
  "json",
  "make",
  "cmake",
  "proto",
  "python",
  "scss",
  "toml",
  "typescript",
  "tsx",
  "java",
  "javascript",
  "yaml",
}
ts.setup({ ensure_installed = languages, highlight = { enable = true } })
