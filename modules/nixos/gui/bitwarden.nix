# bitwarden-desktop 一式 (install + insecure 許可)。
#
# insecureApps 抽象 (modules/nixos/insecure-app.nix) を通じて、
# home-manager.users.<u>.home.packages への追加と
# nixpkgs.config.permittedInsecurePackages への追加が
# この 1 ファイルの宣言から両方派生する。
#
# bitwarden をやめるときは、このファイルを消して common.nix の import 行を消す。
# それだけで install も insecure 許可も両方消える (運用での消し忘れが起きない設計)。
{ settings, lib, ... }:

lib.mkIf settings.features.gui {
  insecureApps.bitwarden = {
    getPackage = pkgs: pkgs.bitwarden-desktop;
    # bitwarden-desktop が依存している electron 39 は EOL のため insecure 扱い。
    # 上流が electron を新しいバージョンに上げたら、この行を削除する。
    # 関連: https://github.com/NixOS/nixpkgs/issues/529107
    insecurePackages = [ "electron-39.8.10" ];
  };
}
