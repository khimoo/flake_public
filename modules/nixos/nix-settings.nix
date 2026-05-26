# Nix・nixpkgs 設定
{ pkgs, inputs, ... }: {
  # NixOS側の非フリーパッケージ許可
  # NOTE: home-managerスタンドアロンモードでは別途 nixpkgs.config.allowUnfree = true が必要
  #       （modules/home-manager/core.nix で設定済み）
  #       NixOSモジュールとして使う場合はここの設定がシステム全体に適用される
  nixpkgs.config.allowUnfree = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # wheel グループのユーザを nix-daemon の trusted-users にする。
  # リモートビルダとして使われる側で必要（`nixos-rebuild --build-host` で
  # 接続してくるユーザが trusted でないと、署名なしの派生物の構築や
  # ストアパス転送が制限される）
  nix.settings.trusted-users = [ "@wheel" ];

  # ガベージコレクション設定
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  nix.settings.auto-optimise-store = true;

  # システムパッケージ
  environment.systemPackages = with pkgs; [
    inputs.home-manager.packages.${pkgs.stdenv.hostPlatform.system}.home-manager # manageHome = falseの人もhome-manager使えるようにしてる
    gparted
    gnomeExtensions.gsconnect
  ];

  programs.adb.enable = true;
}
