# 数式を latex2text で Unicode に近似する。
def writes(neovim):
    return [write(neovim, {"feature": "render_markdown", "packages": [pkg("python3Packages.pylatexenc")]})]
