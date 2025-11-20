" outline bufferの設定はinit.vim参照

" typstとかで数学モードのとき<leader>-で箇条書きするようにする=======
" nnoremap <leader>- :<C-u>call DollertoHyphen()<CR>
" function! DollertoHyphen()
"   execute 'normal! kA $'
"   execute 'normal! jI - $'
"   execute 'normal! A $'
"   execute 'normal! jI$'
" endfunction
" ===================================================================
" ↑ これもnvim surroundでいいな


" " <leader>$で上下に$を追加する=======================================
" nnoremap <leader>$ :<C-u>call AddDollarSigns()<CR>
" function! AddDollarSigns()
"   execute 'normal! kA$'
"   execute 'normal! jo$'
"   execute 'normal! k'
" endfunction
" " ===================================================================
" ↑ <leader>sySS(nvim surround)で上下に追加できます.


" insert modeで$$で自動で改行させる===================================
" inoremap <C-h> $$<ESC>i
" これもnvim surroundでいいな

" 毎回改行の度にback slashめんどくさい
inoremap <S-CR> \<CR>

" typstでの定理環境の辞書の設定=======================================
" set dictionary+=~/.config/nvim/dictionary/typst.txt
" inoremap <leader># #<C-x><C-k>
" inoremap [[ ("")[<C-R>=CompleteMultiline()<CR>
" function! CompleteMultiline()
"   execute 'normal! i'
"   execute 'normal! o'
"   execute 'normal! o'
"   execute 'normal! i]'
"   execute 'normal! ki'
"   return '' " <C-R>=の返り値は挿入される文字列
" endfunction
" ===================================================================
" インデントしない
set nocindent

" tabはスペース2つにする
set expandtab
set tabstop=2
set shiftwidth=2

" tinymist入れたからこれはいらないかもね
" lua << EOF
" local function typst_preview(file)
"   if vim.recent_typst_file == nil then
"     return
"   end
"   if vim.recent_typst_file == file then
"     return
"   end
"   vim.recent_typst_file = file
"     local vaults_root = vim.vaults_root
"
"     vim.cmd('114514ToggleTerm size=1 dir=%s direction=horizontal name=typst_output', vaults_root)
"     vim.cmd('114514TermExec cmd="kill \\$!"')
"
"     local cmd
"     cmd = string.format('typst watch %s /tmp/typst_output.pdf --root ./ &', file)
"     vim.cmd(string.format('114514TermExec cmd=%s', vim.fn.shellescape(cmd)))
"   end
"
" function vim.typst_preview()
"   -- バッファのファイル名を取得
"   local file = vim.fn.expand('%:p')
"   local vaults_root = vim.vaults_root
"
"   vim.cmd('114514ToggleTerm size=1 dir=%s direction=horizontal name=typst_output', vaults_root)
"   vim.cmd('114514TermExec cmd="kill \\$!"')
"
"   local cmd
"   -- cmd = string.format('typst watch %s /tmp/typst_output.pdf --root ./ --open&', file)
"   cmd = string.format('typst watch %s /tmp/typst_output.pdf --root ./&', file)
"   -- TermExecを実行
"   vim.cmd(string.format('114514TermExec cmd=%s', vim.fn.shellescape(cmd)))
"   vim.recent_typst_file = file
" end
"
" vim.api.nvim_create_autocmd("BufWritePost", {
"   pattern = "*.typ",
"   callback = function() typst_preview(vim.fn.expand('%:p')) end,
" })
" vim.api.nvim_create_autocmd("BufWritePost", {
"   pattern = "*.md",
"   callback = function() typst_preview(vim.fn.expand('%:p')) end,
" })
" EOF
