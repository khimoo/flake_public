{ config, lib, ... }:
{
  imports = [
    ./pomu.nix
  ];
  local.profile = {
    features = {
      gui = true;
      gnome = true;
      ime = true;
    };
  };

  # 素のキーは us と同じで、右 Alt（AltGr）との組み合わせでアクセント付きの文字とデッドキーを打つ。
  # デスクトップの FreeRDP は、右 Alt が AltGr であることを前提に、右 Alt の直後だけキーボードを掴む（docs/architecture/windows-vm.md）。
  dconf.settings."org/gnome/desktop/input-sources".sources = [
    (lib.hm.gvariant.mkTuple [
      "xkb"
      "us+altgr-intl"
    ])
  ];
}
