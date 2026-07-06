# マシン間 SSH の単一の情報源（各マシンの user ed25519 公開鍵レジストリ）。
#
# ここに 1 エントリ (hostname = "ssh-ed25519 ...") を足すだけで、
# modules/nixos/ssh.nix が全ホストの authorized_keys と接続エイリアスを生成し、
# 追加マシンは既存全ホストと相互に SSH できるようになる。
#
# 公開鍵の取得: 対象マシンで `cat ~/.ssh/id_ed25519.pub`
# 同じ鍵は `ssh-to-age` で age 形式に変換すると sops の受信者にもなる
# （その用途は .sops.yaml 側で対に管理する。形式が違うため別ファイル）。
{
  nixos-desktop = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIZU5xQXaTeM6exgLs4/0oTDqzO/xi1np/EozB2RH6m3 pomu@nixos-desktop";
  nixos-spin713 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIlhQ23gVzJ8QMe+2NMWc30SzzcfUizylfM21719newI pomu@nixos-spin713";
  # macOS を追加したら 1 行足す（例: nixos-macbook = "ssh-ed25519 ..."）
}
