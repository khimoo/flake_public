return vim.iter({
  require("plugins.lang.rust"),
  require("plugins.lang.go"),
  require("plugins.lang.markdown"),
  require("plugins.lang.typst"),
}):flatten():totable()
