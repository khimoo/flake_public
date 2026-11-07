# mermaid を mmdc で PNG にし、image.nvim が ImageMagick で縮小して表示する。
def writes(neovim):
    return [write(neovim, {"feature": "diagram", "packages": [pkg("mermaid-cli"), pkg("imagemagick")]})]
