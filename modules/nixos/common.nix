# 共通ホスト設定
# base.nix（どのホストでも要る設定）に、desktop 向けのサブモジュールを足す
# 各サブモジュールは単一の責務を持つ（機能的凝集を目指す）

{ ... }: {
  imports = [
    ./base.nix
    ./boot.nix
    ./networking.nix
    ./desktop.nix
    ./printing.nix
    ./ssh.nix
    ./tailscale.nix
    ./remote-builders.nix
    ./bluetooth.nix
    ./libvirt.nix
    ./audio.nix
    ./sns-block.nix
    ./gnome-transparent-fullscreen.nix
  ];
}
