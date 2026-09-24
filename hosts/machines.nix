# マシン間 SSH の単一の情報源。
#
# LAN 内の machine-to-machine 認証は **全マシン共通の 1 本の鍵** (~/.ssh/id_lan) で行う。
# 実体は secrets/secrets.yaml の lan_ssh_key で、modules/home-manager/secrets.nix が
# switch のたびに書き出す。したがってマシンを増やしても鍵の登録作業は無い——
# age 鍵さえ置けば新マシンは既存全ホストと相互に SSH できる。
#
# hosts はホスト名の一覧。modules/nixos/ssh.nix がここから接続エイリアス
# (`ssh desktop` → nixos-desktop.local) を生成する。マシンの追加/廃棄は 1 行の増減で完結する。
#
# builders はリモートビルドを受けるホストと、その能力。`local.remoteBuilders.enable` を
# 立てたホストが、自分以外のここにあるホストへビルドを回す（modules/nixos/remote-builders.nix）。
{
  hosts = [
    "nixos-desktop"
    "nixos-spin713"
    # macOS を追加したら 1 行足す（例: "nixos-macbook"）
  ];

  builders = {
    nixos-desktop = {
      system = "x86_64-linux";
      # デスクトップ自身の max-jobs（auto = 32 スレッド）と揃える。スロットが埋まると、
      # 呼び出し側は手元でビルドするか（localBuilds = true）、空きを待つ。
      maxJobs = 32;
      # デスクトップの `nix config show system-features` と同じ値にする。載せていない
      # feature を要求する derivation（big-parallel の LLVM など）は、ここに回らない。
      supportedFeatures = [ "benchmark" "big-parallel" "kvm" "nixos-test" ];
    };
  };

  # ~/.ssh/id_lan に対応する公開鍵。各ホストの authorized_keys に入る。
  # 差し替え手順は docs/howtouse/machine-ssh.md を参照。
  lanPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMsQXfS2j/9NtGDBz7EAP4I3DamWH1I6cromNqWOZ2pb pomu@lan";
}
