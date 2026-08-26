return {
  {
    'saghen/blink.cmp',
    version = '*',
    opts = {
      keymap = {
        preset = 'default',
        -- default preset:
        -- <C-space>: 補完メニューを手動で開く / ドキュメント表示トグル
        -- <C-y>: 候補を確定
        -- <C-e>: 補完をキャンセル
        -- <C-n> / <C-p>: 次/前の候補
        -- <C-b> / <C-f>: ドキュメントをスクロール
        -- <C-k>: シグネチャヘルプ表示トグル
        -- <Tab> / <S-Tab>: スニペットの次/前のプレースホルダ

        -- kitty keyboard protocol 対応端末でのみ届く。非対応環境では <C-y> がそのまま残る
        ['<C-CR>'] = { 'select_and_accept', 'fallback' },
      },
      completion = {
        documentation = {
          auto_show = true,
          auto_show_delay_ms = 200,
        },
        ghost_text = {
          enabled = true,
        },
      },
      signature = {
        enabled = true,
      },
      cmdline = {
        enabled = true,
      },
      sources = {
        default = { 'lsp', 'path', 'snippets', 'buffer' },
      },
    },
  },
}
