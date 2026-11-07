# main ブランチは全パーサを `tree-sitter build`（0.26.1 以上）で手元でコンパイルする。
def writes(neovim):
    return [write(neovim, {"feature": "treesitter", "packages": [pkg("tree-sitter"), pkg("stdenv.cc")]})]
