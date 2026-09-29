# 全画面にした半透明のウィンドウの下に黒を敷かない mutter。
# system.replaceDependencies で store パスを置換するので、名前（pname と version）を変えない。
# 理由と外す条件は docs/architecture/gnome-transparent-fullscreen.md。
{ mutter }:

mutter.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./transparent-fullscreen.patch ];
})
