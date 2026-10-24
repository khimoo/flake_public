# memex(Obsidian vault)の完結型ワークフローを、外部 flake(khimoo/memex-nix)から
# 取り込んでこのマシンへ配線する唯一のグルー。
#
# 責務分離:
#   - ワークフロー本体(vault の骨格 —— 分類フォルダ・運用ドキュメント・.obsidian —— の配布と、
#     添付フォルダ同期 / papis 本体・設定・ライブラリ同期)は inputs.memex-nix が所有する。
#     Google Drive の認証情報はどちらの repo も持たず、各マシンの ~/.config/rclone/rclone.conf
#     (`rclone config` で各自が作る)に委ねるので、sops-nix や起動順序の配線は不要。
#   - ここが注入するのは純粋に環境固有の配線だけ: vault の clone 位置(memexRoot)、
#     feature toggle、骨格ミラー先の checkout 位置(vaultSkeletonRepo → mirrorRepo)。
#
# vault フォルダ自体は clone-repos（private-repos.nix）の clone が用意するので、モジュール側の
# initializeVault は既定(false)のまま。有効にすると clone より先に空フォルダを作ってしまう。
{ config, inputs, lib, ... }:

let
  attachmentsOn = config.local.profile.features.memexSync;
  papisOn = config.local.profile.features.referenceSync;
  # 既存 vault の設定と骨格は notes repo の clone が所有する。
  # obsidian feature はアプリを導入し、seed は initializeVault = true の環境に限る。
  obsidianOn = config.local.profile.features.obsidian;
  enabled = attachmentsOn || papisOn || obsidianOn;
in
{
  imports = [ inputs.memex-nix.homeModules.memex ];

  config = lib.mkIf enabled {
    # 古い input が戻っても、notes repo の内容を activation が復元する構成は適用させない。
    assertions = [ {
      assertion = !(config.home.activation ? seedVault);
      message = "clone 管理の vault に seedVault activation は不要です。memex-nix input を更新してください。";
    } ];
    xdg.mimeApps.defaultApplications."x-scheme-handler/obsidian" =
      lib.mkIf obsidianOn "obsidian.desktop";
    services.memex = {
      enable = true;
      # clone-repos が clone するため、骨格の初期化・補充は行わない。
      initializeVault = false;
      vaultDir = config.local.profile.memexRoot;
      attachments.enable = attachmentsOn;
      originals.enable = attachmentsOn;
      # 両PCの実Drive試験と原本の初期化・照合を完了（2026-10-19）。
      originals.autoSync = true;
      papis.enable = papisOn;
      obsidian.enable = obsidianOn;
      # vault の骨格を workflow repo へミラーする mirror-vault の宛先(環境固有 checkout)を注入。
      # null なら PATH に載らない。
      mirrorRepo = config.local.profile.vaultSkeletonRepo;
    };
    # 同期の失敗をデスクトップに通知する。サービスは外部 flake が定義するので、ここで足す。
    systemd.user.services = lib.mkMerge [
      (lib.mkIf attachmentsOn {
        attachments-sync.Unit.OnFailure = config.local.failureNotify.onFailure;
        originals-sync.Unit.OnFailure = config.local.failureNotify.onFailure;
      })
      (lib.mkIf papisOn { papis-sync.Unit.OnFailure = config.local.failureNotify.onFailure; })
    ];
  };
}
