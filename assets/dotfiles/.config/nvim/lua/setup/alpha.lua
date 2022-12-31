local dashboard = require("alpha.themes.dashboard")
math.randomseed(os.time())

local function button(sc, txt, keybind, keybind_opts)
  local b = dashboard.button(sc, txt, keybind, keybind_opts)
  b.opts.hl = "Function"
  b.opts.hl_shortcut = "Type"
  return b
end

local function pick_color()
  local colors = { "String", "Identifier", "Keyword", "Number" }
  return colors[math.random(#colors)]
end

local function footer()
  local total_plugins = #vim.tbl_keys(packer_plugins)
  local datetime = os.date(" %d-%m-%Y   %H:%M:%S")
  return datetime
    .. "   "
    .. total_plugins
    .. " plugins"
    .. "   v"
    .. vim.version().major
    .. "."
    .. vim.version().minor
    .. "."
    .. vim.version().patch
end

dashboard.section.header.val = {
[[                            ,,    ,,                                        ,,                                    ]], 
[[   .g8"""bgd               `7MM    db                           MMP""MM""YMM db                                OO ]],
[[ .dP'     `M                 MM                                 P'   MM   `7                                   88 ]],
[[ dM'       ` ,pW"Wq.    ,M""bMM  `7MM  `7MMpMMMb.  .P"Ybmmm          MM    `7MM  `7MMpMMMb.pMMMb.  .gP"Ya      || ]],
[[ MM         6W'   `Wb ,AP    MM    MM    MM    MM :MI  I8            MM      MM    MM    MM    MM ,M'   Yb     || ]],
[[ MM.        8M     M8 8MI    MM    MM    MM    MM  WmmmP"            MM      MM    MM    MM    MM 8M""""""     `' ]],
[[ `Mb.     ,'YA.   ,A9 `Mb    MM    MM    MM    MM 8M                 MM      MM    MM    MM    MM YM.    ,     ,, ]],
[[  `"bmmmd'  `Ybmd9'   `Wbmd"MML..JMML..JMML  JMML.YMMMMMb         .JMML.  .JMML..JMML  JMML  JMML.`Mbmmd'     db  ]],
[[                                                 6'     dP                                                        ]],
[[                                                 Ybmmmd'                                                          ]],
}
dashboard.section.header.opts.hl = pick_color()

dashboard.section.buttons.val = {
  button("<Leader>f", "  File Explorer"),
  button("<Leader>p", "  Find file"),
  button("<Leader>g", "  Find word"),
  button("<Leader>1", "  Open session"),
  button("<Leader>n", "  New file"),
  button("<Leader>u", "  Update plugins"),
  button("q", "  Quit", "<Cmd>qa<CR>"),
}

dashboard.section.footer.val = footer()
dashboard.section.footer.opts.hl = "Constant"

require("alpha").setup(dashboard.opts)
