# 手段: XKB のキーボード配列の正本。ホストの xkb_layout が無ければ us+altgr-intl を使う。
# 素のキーは us と同じで、右 Alt（AltGr）との組み合わせでアクセント付きの文字とデッドキーを打つ。
# デスクトップの FreeRDP は、右 Alt が AltGr であることを前提に、右 Alt の直後だけキーボードを掴む（docs/architecture/windows-vm.md）。
def public(host):
    layout, _, variant = getattr(host, "xkb_layout", "us+altgr-intl").partition("+")
    return {"layout": layout, "variant": variant}
