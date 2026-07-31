# Zettelkasten(Obsidian vault)の完結型ワークフローを、外部 flake(khimoo/zettelkasten-workflow)から
# 取り込んでこのマシンへ配線する唯一のグルー。
#
# 責務分離:
#   - ワークフロー本体(vault の骨格 —— 分類フォルダ・運用ドキュメント・.obsidian —— の配布と、
#     添付フォルダ同期 / papis 本体・設定・ライブラリ同期)は inputs.zettelkasten が所有する。
#     Google Drive の認証情報はどちらの repo も持たず、各マシンの ~/.config/rclone/rclone.conf
#     (`rclone config` で各自が作る)に委ねるので、sops-nix や起動順序の配線は不要。
#   - ここが注入するのは純粋に環境固有の配線だけ: vault の clone 位置(zettelkastenRoot)、
#     feature toggle、骨格ミラー先の checkout 位置(vaultSkeletonRepo → mirrorRepo)。
#
# vault フォルダ自体は private-repos.nix の clone が用意するので、モジュール側の
# initializeVault は既定(false)のまま。有効にすると clone より先に空フォルダを作ってしまう。
{ inputs, settings, lib, ... }:

let
  attachmentsOn = settings.features.zettelkastenSync or false;
  papisOn = settings.features.referenceSync or false;
  # obsidian は同期(rclone/gdrive)に依存しない独立の関心。Obsidian 本体を入れ、vault に
  # .obsidian 設定を非破壊で配置するだけで、Nix さえあれば同期なしでも成立する。
  # 骨格(分類フォルダ・運用ドキュメント)の seed はこの feature ではなく enable 側に載るので、
  # 同期だけ有効なホストでも骨格は配置される(既存ファイルは触らないので実質 no-op)。
  obsidianOn = settings.features.obsidian or false;
  enabled = attachmentsOn || papisOn || obsidianOn;
in
{
  imports = [ inputs.zettelkasten.homeModules.zettelkasten ];

  config = lib.mkIf enabled {
    services.zettelkasten = {
      enable = true;
      vaultDir = settings.zettelkastenRoot;
      attachments.enable = attachmentsOn;
      papis.enable = papisOn;
      obsidian.enable = obsidianOn;
      # vault の骨格を workflow repo へミラーする mirror-vault の宛先(環境固有 checkout)を注入。
      # null なら PATH に載らない。
      mirrorRepo = settings.vaultSkeletonRepo or null;
    };
  };
}
