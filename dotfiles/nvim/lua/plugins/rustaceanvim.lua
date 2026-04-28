return {
  {
    'mrcjkb/rustaceanvim',
    version = '^5',
    lazy = false,
    dependencies = { "mfussenegger/nvim-dap" },
    init = function()
      local codelldb_path = tostring(os.getenv("CODELLDB_PATH") or "codelldb")
      local liblldb_path = vim.fn.fnamemodify(codelldb_path, ':h:h') .. '/lldb/lib/liblldb.so'

      vim.g.rustaceanvim = {
        dap = {
          adapter = require('rustaceanvim.config').get_codelldb_adapter(codelldb_path, liblldb_path),
        },
      }
    end,
  },
}
