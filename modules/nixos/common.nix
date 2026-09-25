# 共通ホスト設定
# 複数のNixOSホストで共有されるサブモジュールを集約する
# 各サブモジュールは単一の責務を持つ（機能的凝集を目指す）

{ specialArgs, ... }: {
  imports = [
    ./boot.nix
    ./networking.nix
    ./locale.nix
    ./desktop.nix
    ./printing.nix
    ./users.nix
    ./nix-settings.nix
    ./ssh.nix
    ./tailscale.nix
    ./remote-builders.nix
    ./bluetooth.nix
    ./libvirt.nix
    ./audio.nix
    ./sns-block.nix
    ./permit-insecure.nix
    ./codex.nix
    ./agent-instructions.nix
    ./claude-managed-settings.nix
  ];

  # システム状態バージョン
  system.stateVersion = specialArgs.settings.stateVersion;
}
