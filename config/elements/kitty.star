# smart-splits.nvim の kitty backend が kitty @ kitten で呼ぶスクリプト。プラグイン同梱の
# install-kittens.bash は ~/.config/kitty/ へ命令的にコピーする作りだが、nixpkgs の vimPlugins が
# 同じファイルを持っているので宣言的に置ける。Neovim 側（nvim_smart_splits.star）と同じパッケージ。

def user_config(checkout, gui):
    def kitten(name):
        return concat(pkg("vimPlugins.smart-splits-nvim"), "/kitty/" + name)
    return {"home": {
        "home.packages": [pkg("kitty")],
        # ファイル単位の symlink なので、同じ ~/.config/kitty/ に font.conf と kitten を置ける。
        ("xdg", "configFile", "kitty/kitty.conf", "source"): outOfStoreLink(checkout.root + "/modules/home-manager/gui/kitty/kitty.conf"),
        # kitty.conf の include が読む。
        ("xdg", "configFile", "kitty/font.conf", "text"): "font_family " + gui.terminal_font["name"] + "\n",
        # kitty.conf の neighboring_window / relative_resize が読む。
        ("xdg", "configFile", "kitty/neighboring_window.py", "source"): kitten("neighboring_window.py"),
        ("xdg", "configFile", "kitty/relative_resize.py", "source"): kitten("relative_resize.py"),
        ("xdg", "configFile", "kitty/split_window.py", "source"): kitten("split_window.py"),
    }}
