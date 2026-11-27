# 手段: CapsLock で日本語 ⇔ 英数を切り替える（Meltype）。
# Meltype の fcitx5 アドオン（1.7.1）は CapsLock を受け取らず、US 配列の XKB には 半角/全角 の keysym が無い。
# また 1.7.1 の本体は、修飾キーなしの切り替えキーに 半角/全角 しか登録できない（「かな」を config.json に書いても外される）。
# そこで keyd で CapsLock を「かな」（Hiragana_Katakana）に変え、アドオンが「かな」を 半角/全角 として扱う
# （packages/meltype/kana-as-hankaku.patch）。Meltype の設定は要らない。
# CapsLock 本来のロックは使えなくなる。spin713 の内蔵キーボードは keyd の既定キーボードから外してあるので対象外。
requires = ["japanese_input"]
needs = ["nixos_system"]

def writes(keyd):
    return [write(keyd, default_layers = {"main": {"capslock": "katakanahiragana"}})]
