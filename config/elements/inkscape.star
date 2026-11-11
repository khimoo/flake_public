requires = ["gui"]

def config(checkout):
    return {"home": {
        "home.packages": [pkg("inkscape")],
        # 新規文書の既定テンプレート。checkout への symlink なので、GUI の「デフォルトテンプレートとして
        # 設定」がリポジトリのファイルを直接書き換える。表示倍率やウィンドウ寸法も書き込まれるので、
        # commit 前に差分を確かめる（docs/howtouse/inkscape.md）。
        ("xdg", "configFile", "inkscape/templates/default.svg", "source"): outOfStoreLink(checkout.root + "/modules/home-manager/gui/inkscape/default.svg"),
    }}
