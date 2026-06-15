# home-manager 側で宣言された insecure 許可エントリを集約し、
# NixOS の nixpkgs.config.permittedInsecurePackages に転記する。
#
# 動機:
#   GUI アプリの install は home-manager (modules/home-manager/gui/apps.nix) の
#   責務だが、一部のアプリ (例: bitwarden-desktop) は EOL の依存 (electron 39 等)
#   を抱えており、NixOS の nixpkgs.config.permittedInsecurePackages に追加しないと
#   build できない。素朴に書くと「install (home-manager 側) と insecure 許可
#   (NixOS 側)」が別ファイルに分散し、片方を消し忘れる運用リスクが生じる。
#
# 設計:
#   アプリ宣言の一部として `insecurePackages = [...]` を持たせる。
#   home-manager 側の apps.nix がそれを `local.insecurePackages` option として
#   export し、このファイル (NixOS module) が全 home-manager users の値を集約して
#   nixpkgs.config.permittedInsecurePackages に設定する。
#
# 依存方向: home-manager (ユーザ環境) → NixOS (OS)。
#   アプリ管理は home-manager 側で完結し、insecure 許可だけが OS 側に届く。
#   useGlobalPkgs = true のため home-manager から直接 nixpkgs.config を設定する
#   ことはできないので、NixOS module 側でこの転記を行う必要がある。
{ config, lib, ... }:
{
  nixpkgs.config.permittedInsecurePackages = lib.unique (
    lib.concatLists (
      lib.mapAttrsToList (_: userCfg: userCfg.local.insecurePackages or [ ])
        config.home-manager.users
    )
  );
}
