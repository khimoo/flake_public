# Nix・nixpkgs 設定
{ pkgs, inputs, ... }: {
  # NixOS側の非フリーパッケージ許可
  # NOTE: home-managerスタンドアロンモードでは別途 nixpkgs.config.allowUnfree = true が必要
  #       （lib/configurations.nix の mkHome で設定）
  #       NixOSモジュールとして使う場合はここの設定がシステム全体に適用される
  nixpkgs.config.allowUnfree = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # wheel グループのユーザを nix-daemon の trusted-users にする。
  # `nixos-rebuild --build-host --sudo` はビルダ側でも呼び出し側でも一般ユーザとして
  # ストアに書き込む。trusted でないと、ビルダ側は署名なしの派生物の構築を、
  # 呼び出し側は転送されてきた成果物の取り込みを拒否する。
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
