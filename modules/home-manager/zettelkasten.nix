# Zettelkasten(Obsidian vault)の完結型ワークフローを、外部 flake(khimoo/zettelkasten)から
# 取り込んでこのマシンへ配線する唯一のグルー。
#
# 責務分離:
#   - ワークフロー本体(添付フォルダ同期 / papis 本体・設定・ライブラリ同期)と secret の暗号文・
#     実行時復号は inputs.zettelkasten が所有する。同期スクリプト自身が実行のたびに
#     secrets/rclone.yaml をこのマシンの SSH 鍵(~/.ssh/id_ed25519 を ssh-to-age 変換)で復号する
#     ため、sops-nix や起動順序の配線は不要。
#   - ここが注入するのは純粋に環境固有の配線だけ: vault の clone 位置(zettelkastenRoot)と
#     feature toggle。
{ inputs, settings, lib, ... }:

let
  attachmentsOn = settings.features.zettelkastenSync or false;
  papisOn = settings.features.referenceSync or false;
  # obsidianSeed は同期(rclone/gdrive)に依存しない独立の関心。vault に .obsidian 設定を
  # 非破壊で配置するだけで、Nix さえあれば同期なしでも成立する。ゆえに別 feature で持つ。
  obsidianOn = settings.features.obsidianSeed or false;
  enabled = attachmentsOn || papisOn || obsidianOn;
in
{
  imports = [ inputs.zettelkasten.homeManagerModules.zettelkasten ];

  config = lib.mkIf enabled {
    services.zettelkasten = {
      enable = true;
      zettelkastenRoot = settings.zettelkastenRoot;
      attachments.enable = attachmentsOn;
      papis.enable = papisOn;
      obsidian.enable = obsidianOn;
    };
  };
}
