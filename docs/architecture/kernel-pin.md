# カーネルの 7.0 系ピン留め (nixos-desktop)

設定ファイル: `hosts/nixos-desktop/hardware.nix` の `boot.kernelPackages`

**upstream カーネルの回帰が解消したら `linuxPackages_latest` に戻せる。**

## 問題

nixos-desktop (ASUS PRIME X399-A / Threadripper) で shutdown しても電源が切れない。OS 側の
poweroff シーケンスはクリーンに完走している（systemd が `System Power Off` に到達しログも正常終了）
のに、その後カーネルが firmware に渡す電源断（ACPI S5）が効かず、本体が暖かいまま・ファンが回り続け、
電源ボタン長押しでしか切れない。

X399/Threadripper は firmware の ACPI S5 実装にバグがあり、S5 突入で止まるのは OS を問わず起きる既知の
挙動（FreeBSD でも同症状の報告あり）。カーネル 7.0 系では発生せず、7.1 系に上げてから出始めた
（7.0.12 で正常 → 7.1.2 で発症）ことから、7.1 系がこの firmware バグを踏むようになったと見られる。

## 判断

`linuxPackages_latest`（7.1 系）をやめ、`linuxPackages_7_0`（7.0.14）にピン留めする。

- 7.0 系は発症前の系列で、回帰の引き金を避けられる。nixos-25.11 の中では 7.0.x の点リリースを
  引き続き受け取れる。
- このマシンで `linuxPackages_latest` を使っていたのは blender-hip / AMD GPU のため。7.0.14 は
  6.12 LTS より新しく、GPU 用途にも十分新しい。
- カーネルパラメータでの回避（`acpi=force` 等）は firmware バグ相手で当たり外れが大きく、確実な
  回避策として確認できていない。FreeBSD 側は ACPI ではなく EFI で電源断するカーネルパッチで解決して
  いるが、Linux には同等の綺麗な手が無い。
- BIOS が 2019 年の 1203 と古く、後継 BIOS があれば root cause 側を直せる可能性はある（未確認）。

7.0.14 でも poweroff が直らなければ原因は 7.1 系の回帰ではなく別（firmware/電源設定側）にある、
という切り分けにもなる。

## 見直しの契機

- NixOS のリリースを 25.11 から上げるとき: `linuxPackages_7_0` が消える可能性があるので、その時点の
  `linuxPackages_latest` で poweroff が直っているか再確認し、直っていればピンを外す。
- 7.1 以降で当該回帰が upstream 修正されたと分かったとき。

## 関連 / 参考

- [Kernel 7.0 broke the ACPI poweroff? — Arch Linux Forums](https://bbs.archlinux.org/viewtopic.php?pid=2299070)
- [ACPI shutdown not working on AMD X399/Threadripper — FreeBSD Forums](https://forums.freebsd.org/threads/acpi-shutdown-not-working-on-amd-x399-threadripper.69065/)
