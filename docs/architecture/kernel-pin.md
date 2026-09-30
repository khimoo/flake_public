# nixos-desktop のカーネル

設定ファイル: `hosts/nixos-desktop/hardware.nix`（`boot.kernelPackages` は指定せず、NixOS のデフォルトを使用）

**NixOS デフォルトの LTS（nixos-26.05 では 6.18）を使用する。`linuxPackages_latest` に移行する前に、実機で正常に電源が切れることを確認すること。**

## 問題

nixos-desktop（ASUS PRIME X399-A / Threadripper）において、シャットダウンを実行しても電源が切れない現象が発生した。OS 側のシャットダウン処理（poweroff シーケンス）は正常に完了しており（systemd が `System Power Off` に到達し、ログも正常に終了）、その後カーネルからファームウェアに渡される電源オフ（ACPI S5）の処理が機能していない。そのため、本体が発熱したままファンが回り続け、電源ボタンを長押ししなければ電源を落とせない状態になる。

X399/Threadripper はファームウェアの ACPI S5 実装にバグがあり、S5（電源オフ状態）への移行時にフリーズするのは、OS を問わず発生する既知の挙動である（FreeBSD でも同様の症状が報告されている）。カーネル 7.0 系では発生せず、7.1 系にアップデートしてから発生し始めた（7.0.12 では正常、7.1.2 で発生）ことから、7.1 系のカーネルがこのファームウェアのバグを踏むようになったと考えられる。

## 判断

nixos-25.11 を使用している間は `linuxPackages_7_0` に固定していた。しかし、nixos-26.05 では 7.0 系と 7.1 系が EOL（サポート終了）となり nixpkgs から削除された。今回は、デフォルトの `linuxPackages`（6.18 LTS）と `linuxPackages_latest`（7.2）を候補として比べた。

今回はデフォルトの 6.18 LTS を選択した（2026-09-30）。

- 6.18 は不具合が発生した 7.1 系より前のバージョンであり、LTS 版のため nixos-26.05 の運用期間中に削除される心配がない。
- `linuxPackages_latest` は 26.05 の運用中にさらに新しいメジャーバージョンへアップデートされるため、仮に現在の不具合が解消されていても、将来のアップデートで再発する可能性がある。
- 本マシンの GPU（AMD Navi 23、PCI ID `1002:73ff`）は、6.18 カーネルでも十分に動作する。

なお、6.18 で実際に電源が正常に切れるかどうかは、実機で検証するまで不明である。

## 見直しの契機

- 時間があるときに `linuxPackages_latest` にアップデートしてシャットダウンを試し、正常に電源が切れるようであれば latest への移行を検討する。
- 6.18 でも電源が切れない場合。7.1 系に固有の回帰という仮説を見直し、カーネル、ファームウェア、電源の設定のどこに原因があるかを切り分ける。
- BIOS のアップデート等により、ファームウェア側のバグが修正されたことが確認できたとき（現在の BIOS バージョンは 2019 年リリースの 1203）。

## 関連 / 参考

- [Kernel 7.0 broke the ACPI poweroff? — Arch Linux Forums](https://bbs.archlinux.org/viewtopic.php?pid=2299070)
- [ACPI shutdown not working on AMD X399/Threadripper — FreeBSD Forums](https://forums.freebsd.org/threads/acpi-shutdown-not-working-on-amd-x399-threadripper.69065/)
