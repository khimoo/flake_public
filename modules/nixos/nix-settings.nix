# Nix・nixpkgs 設定
{ pkgs, inputs, ... }: {
  # NixOS側の非フリーパッケージ許可
  # NOTE: home-managerスタンドアロンモードでは別途 nixpkgs.config.allowUnfree = true が必要
  #       （modules/home-manager/core.nix で設定済み）
  #       NixOSモジュールとして使う場合はここの設定がシステム全体に適用される
  nixpkgs.config.allowUnfree = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

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
