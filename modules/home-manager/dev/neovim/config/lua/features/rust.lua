return {
  {
    'mrcjkb/rustaceanvim',
    version = '^5',
    lazy = false,
    init = function()
      -- 生成元: modules/home-manager/dev/neovim/features.nix
      local codelldb_path = require("config.nix").data.rust.codelldb
      local suffix = vim.fn.has('macunix') == 1 and 'dylib' or 'so'
      local liblldb_path = vim.fn.fnamemodify(codelldb_path, ':h:h') .. '/lldb/lib/liblldb.' .. suffix

      vim.g.rustaceanvim = {
        dap = {
          adapter = require('rustaceanvim.config').get_codelldb_adapter(codelldb_path, liblldb_path),
        },
      }
    end,
  },
}
