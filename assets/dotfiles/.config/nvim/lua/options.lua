local options = {
	relativenumber = true,
	shiftwidth = 2,
	tabstop = 2,
	number = true,
	swapfile = false,
	fileencoding = "utf-8",
	undofile = true,
	expandtab = true,
	updatetime = 300
}

for k, v in pairs(options) do
	vim.opt[k] = v
end
