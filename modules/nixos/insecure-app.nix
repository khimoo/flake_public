# insecure 許可を必要とする user-facing パッケージを宣言するための抽象モジュール。
#
# 動機:
#   ある user app (例: bitwarden-desktop) が EOL の dependency (例: electron 39) を
#   抱えていると、nixpkgs.config.permittedInsecurePackages に追加しないと build が
#   通らない。素朴に書くと「install (home-manager 側) と insecure 許可 (NixOS 側)」が
#   別ファイルになり、片方を消し忘れる運用リスクが発生する。
#
#   この抽象を経由すると 1 宣言で両側を結びつけられる:
#       insecureApps.<name> = {
#         getPackage = pkgs: pkgs.<package>;
#         insecurePackages = [ "<insecure-pkg-name>" ];
#       };
#   宣言を削除すれば install も insecure 許可も同時に消える。
#
# なぜ getPackage が関数型 (`pkgs -> package`) か:
#   package を直接書くと submodule 評価時に derivation が forced され、
#   nixpkgs.config が確定する前に check-meta が走って失敗する (chicken-and-egg)。
#   関数にすることで permittedInsecurePackages の集計 (insecurePackages のみを読む)
#   は package を forced せずに完了でき、pkgs の fixed point が解決される。
#   home.packages 評価時に初めて getPackage pkgs が呼ばれ、その時点では
#   insecure 許可が確定しているので check-meta を通過する。
{ config, lib, pkgs, ... }:

let
  apps = lib.attrValues config.insecureApps;
in
{
  options.insecureApps = lib.mkOption {
    default = { };
    description = "User packages that require nixpkgs.config tweaks (insecure allow).";
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        getPackage = lib.mkOption {
          type = lib.types.functionTo lib.types.package;
          description = "Function `pkgs -> package`. Wrapped to avoid forcing the derivation before nixpkgs.config is finalized.";
        };
        insecurePackages = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = "Strings to add to nixpkgs.config.permittedInsecurePackages.";
        };
      };
    });
  };

  config = {
    nixpkgs.config.permittedInsecurePackages =
      lib.unique (lib.concatMap (a: a.insecurePackages) apps);

    # home-manager.sharedModules は全 home-manager ユーザに適用される。
    # ユーザ別の出し分けが必要になったら、別オプションでユーザ名リストを取れるようにする。
    home-manager.sharedModules = [
      { home.packages = map (a: a.getPackage pkgs) apps; }
    ];
  };
}
