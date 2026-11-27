# 手段: 左 Alt+Space で日本語 ⇔ 英数を切り替える（Meltype）。
# US 配列の XKB には 半角/全角 の keysym が無い。
# また 1.7.1 の本体は、修飾キーなしの切り替えキーに 半角/全角 しか登録できない（「かな」を config.json に書いても外される）。
# そこで keyd で左 Alt+Space を単体の「かな」（Hiragana_Katakana）に変え、アドオンが「かな」を 半角/全角 として扱う
# （packages/meltype/kana-as-hankaku.patch）。Meltype の設定は要らない。
requires = ["japanese_input"]
needs = ["nixos_system"]

_ALT_BINDINGS = {"space": "katakanahiragana"}

def public():
    return {"alt_bindings": _ALT_BINDINGS}

def writes(keyd):
    return [write(keyd, default_layers = {"alt": _ALT_BINDINGS})]
