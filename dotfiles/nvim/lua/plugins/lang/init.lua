return vim.iter({
  require("plugins.lang.rust"),
  require("plugins.lang.go"),
}):flatten():totable()
