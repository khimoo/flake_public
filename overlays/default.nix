# 一時的な overlay 集。不要になったものから削除すること。
[
  # TODO: mypaint のバージョンが 2.0.1 より上がるか、nixpkgs 側でパッチが取り込まれたら削除する。
  # 背景: PyGObject 3.51.0 で GLib enum が stdlib enum ベースに変わり、
  #       value_name 属性が廃止された。MyPaint 2.0.1 はこれに対応していない。
  # 参照: https://github.com/mypaint/mypaint/issues/1292
  (final: prev: {
    mypaint = prev.mypaint.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        substituteInPlace lib/glib.py \
          --replace-warn 'k.value_name' 'k.name'
      '';
    });
  })
]
