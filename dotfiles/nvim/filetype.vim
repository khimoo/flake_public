augroup filetypedetect
  " 拡張子 .re のファイルを Re:VIEW ファイルと判定
  au BufNewFile,BufRead *.re        setf review
  " luaならlua
  au BufNewFile,BufRead *.lua       setf lua
  function s:is_telekasten()
      " 絶対パスにmath_with_typが含まれていたらtypstにする
      return match(expand('%:p'), 'vaults/math_with_typ') != -1
  endfunction
  " .mdファイルを開いたとき、Bufferの絶対パスにvaults/math_with_typが含まれていたらtypstにする
  au BufNewFile,BufRead *.md        if <SID>is_telekasten() | setf typst | endif
augroup END
