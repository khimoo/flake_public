# マシンの構成、マシン間 SSH、リモートビルドの単一の情報源。
# LAN 認証は全マシン共通の ~/.ssh/id_lan で行い、secrets.nix が lanSsh を選んだユーザーへ配布する。
# マシンを増やしても鍵の登録作業はなく、age 鍵を置けば既存の全ホストと相互に SSH できる。
# sshUser を持つマシンから SSH 接続名、builder を持つマシンからリモートビルダー、
# nixos を持つマシンから NixOS 構成を生成する。追加・廃棄は一項目の増減で管理する。
{
  machines = {
    nixos-desktop = {
      system = "x86_64-linux";
      sshUser = "pomu";
      builder = {
        # デスクトップ自身の max-jobs（auto = 32 スレッド）と揃える。スロットが埋まると、
        # 呼び出し側は手元でビルドするか（localBuilds = true）、空きを待つ。
        maxJobs = 32;
        # デスクトップの `nix config show system-features` と同じ値にする。載せていない
        # feature を要求する derivation（big-parallel の LLVM など）は、ここに回らない。
        supportedFeatures = [ "benchmark" "big-parallel" "kvm" "nixos-test" ];
      };
      nixos = {
        users =
          map
            (
              u:
              u
              // {
                homeFile = ./nixos-desktop + "/home-manager-${u.username}.nix";
              }
            )
            [
              {
                username = "pomu";
                isAdmin = true;
              }
              {
                username = "mase";
                isAdmin = false;
                manageHome = false;
                initialHashedPassword = "$6$jQHubQo9MXPX15.x$LSWMJBiOQT75T/HOeMyKlFmWZjl.wTi7CA.m02uFPPJqssvKCMq1..6fGYdjm7HMJhhBAIl1Vbpkuq92gaVbH/";
              }
            ];
        timezone = "Asia/Tokyo";
        stateVersion = "25.05";
      };
    };
    nixos-spin713 = {
      system = "x86_64-linux";
      sshUser = "pomu";
      nixos = {
        users = [
          {
            username = "pomu";
            isAdmin = true;
            homeFile = ./nixos-spin713/home.nix;
          }
        ];
        timezone = "Asia/Tokyo";
        stateVersion = "25.05";
      };
    };
    nixos-work-wsl = {
      system = "x86_64-linux";
      nixos = {
        users = [
          {
            username = "nixos";
            isAdmin = true;
            homeFile = ./nixos-work-wsl/home.nix;
          }
        ];
        timezone = "Asia/Tokyo";
        stateVersion = "26.05";
      };
    };
  };

  # ~/.ssh/id_lan に対応する公開鍵。各ホストの authorized_keys に入る。
  # 差し替え手順は docs/howtouse/machine-ssh.md を参照。
  lanPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMsQXfS2j/9NtGDBz7EAP4I3DamWH1I6cromNqWOZ2pb pomu@lan";
}
