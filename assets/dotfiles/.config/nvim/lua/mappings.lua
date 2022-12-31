local function map(mode, lhs, rhs, opts)
  local options = { noremap = true }
  if opts then
    options = vim.tbl_extend("force", options, opts)
  end
  vim.api.nvim_set_keymap(mode, lhs, rhs, options)
end

-- Map leader to space
vim.g.mapleader = " "

-- Switch Session
map("n", "<Leader>1", ":SearchSession<CR>")

-- Telescope

local km = vim.keymap

-- Add moves of more than 5 to the jump list
km.set("n", "j", [[(v:count > 5 ? "m'" . v:count : "") . 'j']], { expr = true, desc = "if j > 5 then add to jumplist" })
km.set("n", "<leader>p", function()
  require("telescope.builtin").find_files()
end)
km.set("n", "<leader>r", function()
  require("telescope.builtin").registers()
end)
km.set("n", "<leader>g", function()
  require("telescope.builtin").live_grep()
end)
km.set("n", "<leader>b", function()
  require("telescope.builtin").buffers()
end)
km.set("n", "<leader>j", function()
  require("telescope.builtin").help_tags()
end)
km.set("n", "<leader>h", function()
  require("telescope.builtin").git_bcommits()
end)
km.set("n", "<leader>f", function()
  require("telescope").extensions.file_browser.file_browser()
end)
km.set("n", "<leader>s", function()
  require("telescope.builtin").spell_suggest()
end)
km.set("n", "<leader>i", function()
  require("telescope.builtin").git_status()
end)
km.set("n", "<leader>ca", function()
  require("telescope.builtin").lsp_code_actions()
end)
km.set("n", "<leader>cs", function()
  require("telescope.builtin").lsp_document_symbols()
end)
km.set("n", "<leader>cd", function()
  require("telescope.builtin").lsp_document_diagnostics()
end)
km.set("n", "<leader>cr", function()
  require("telescope.builtin").lsp_references()
end)

-- Update Plugins
map("n", "<Leader>u", ":PackerSync<CR>")

-- Source nvimrc file
map("n", "<Leader>sv", ":luafile %<CR>")

-- Quick new file
map("n", "<Leader>n", "<cmd>enew<CR>")

-- Easier file save
map("n", "<Leader>w", "<cmd>:w<CR>")
map("n", "<Leader>q", "<cmd>:q<CR>")

-- Tab to switch buffers in Normal mode
map("n", "<Tab>", ":bnext<CR>")
map("n", "<S-Tab>", ":bprevious<CR>")
