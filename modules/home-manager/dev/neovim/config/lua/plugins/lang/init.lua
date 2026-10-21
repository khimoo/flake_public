return vim.iter({
  require("plugins.lang.go"),
  require("plugins.lang.markdown"),
  require("plugins.lang.typst"),
}):flatten():totable()
