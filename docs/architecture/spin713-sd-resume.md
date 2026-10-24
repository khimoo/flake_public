# spin713 の /nix を置いた SD カードと復帰時のエラー

設定ファイル: [hosts/nixos-spin713/nix-sd-card.nix](../../hosts/nixos-spin713/nix-sd-card.nix)（`services.udev.extraRules`）

**`/nix` のパーティションを内蔵 SD カードリーダー（Genesys `05e3:0747`）で使っているとき、その SCSI ディスクに `manage_system_start_stop=1` を設定している。効果は実機で確かめずに適用したので、復帰後のログで効果を確かめ、効果がなければ外す。**

## 問題

spin713 は `/nix` を内蔵 SD カードリーダー（USB 接続）に入れた SD カードに置いている。
s2idle から復帰すると、リーダーが UNIT ATTENTION（ASC 0x28、「Not ready to ready change, medium may have changed」）を返す。
2026-10-19 から 2026-10-24 までの起動では、7 回の復帰のうち 6 回でこの応答が出て、6 回とも復帰後 0.2〜2.3 秒の間 `/nix` の読み出しが I/O エラーになった。
この間に `/nix/store` のプログラムを起動したプロセスは、失敗したまま戻らない。
観測した例は、ロック画面の解除の認証、`sleep-actions.service` の ExecStop、GNOME Shell からの `systemctl`、fcitx5 である。
ext4 にも EIO が記録されるが、次の起動時の fsck で消える（2026-10-19 のエラーで確認）。

## カーネルの挙動（Linux v6.18）

- `drivers/scsi/scsi_lib.c` の `scsi_io_completion_action()` は、取り外し可能なデバイスが UNIT ATTENTION を返すと、メディアが入れ替わったとみなして `changed` を立て、そのコマンドを失敗させる。
- `drivers/scsi/sd.c` は、`changed` が立っている間の読み書きを「device offline or changed」で拒否する。`changed` を下ろすのは、メディアのポーリング（`block.events_dfl_poll_msecs`、既定 2000 ms）で実行される `sd_check_events()` である。
- カーネル内部から送るコマンド（passthrough）が UNIT ATTENTION を受けた場合は、`scsi_noretry_cmd()` で終了し、`scsi_io_completion_action()` は呼ばれない。そのため `changed` は立たない。

## 判断

`manage_system_start_stop=1` にすると、sd ドライバはシステムのスリープ時に STOP UNIT を、復帰処理の中（プロセスが再開する前）に START UNIT を送る。
リーダーが UNIT ATTENTION を START UNIT への応答として返せば、内部コマンドが受け取るので `changed` は立たず、その後の読み出しは成功するはずである。
リーダーが START UNIT より後に UNIT ATTENTION を返す場合は効果がない。
どちらになるかはソースからは決まらない。
試験の手間を省くため、副作用を確認したうえで、試さずに適用した（ユーザーの判断）。

udev ルールは、`/nix` のファイルシステムの UUID とリーダーの USB ID の両方で対象を選ぶ。
対策が要るのは「`/nix` をこのリーダーで使っている場合」だけだからである。
UUID は `fileSystems."/nix"` と同じ値から作るので、カードを替えて UUID を書き換えるとルールも一緒に追従する。
USB ID だけで選ぶ案には、媒体を読まずに設定できる利点があるが、`/nix` との依存がルールに表れないので採らなかった。
このルールはパーティションから SCSI ディスクへたどる sysfs の構造を前提にしているので、LUKS や LVM を間に挟む構成には追従しない。

`/nix` をそのまま eMMC へ移す案は、`/nix` の使用量（143 GB）が eMMC の `/`（48 GB）を超えるので採れない。
必要なストアだけなら eMMC に収まるかは測っていない。

## 副作用（Linux v6.18 の `drivers/scsi/sd.c` と `drivers/scsi/scsi_pm.c` で確認）

- スリープ時の STOP UNIT の失敗は `sd_suspend_common()` で無視されるので、スリープは中断しない。
- 復帰時の START UNIT が失敗すると、カーネルログに「Start/Stop Unit failed」が出て、復帰のコールバックは -EIO を返す。`scsi_bus_resume_common()` は結果によらず `scsi_device_resume()` を呼ぶので、ディスクはそのまま使える。
- リーダーが START UNIT に応答しないと、タイムアウト（1 回あたり `SD_TIMEOUT` の 30 秒）まで復帰が待たされる。このリーダーは復帰直後の読み出しにすぐ応答しているので起きにくいと見ているが、確かめていない。
- hibernate では、電源を切るとき（poweroff）と復元するとき（restore）にも同じコマンドを送る。イメージを作る freeze と thaw では送らない。

## 効果の確かめ方と見直しの契機

udev ルールは起動時にデバイスが追加されるときに適用され、switch では既存のデバイスに再適用されない。
switch 後に再起動せず試すなら `echo 1 | sudo tee /sys/class/scsi_disk/0:0:0:0/manage_system_start_stop` を実行する。
設定されているかは、同じファイルを `cat` して `1` が返るかで確かめる。
スリープから復帰したら、次のコマンドでその起動のカーネルログを見る。

```sh
journalctl -b -k -o short-iso | grep -E 'PM: suspend exit|Start/Stop Unit failed|medium may have changed|offline or changed'
```

- 復帰後に「offline or changed」が出なければ効果がある。START UNIT が UNIT ATTENTION を受けた場合は「Start/Stop Unit failed」と「medium may have changed」が並んで出るが、これは想定どおりである。
- 復帰後に「offline or changed」が出続けるなら効果がないので、udev ルールを外す。そのうえで、別のカードリーダーか外付け SSD に `/nix` を置く案と、必要なストアだけを eMMC に置けるかを検討する。
- 復帰に時間がかかるようになったら START UNIT のタイムアウトを疑い、上のログで「PM: suspend exit」と前後の時刻を比べる。

一時的に元へ戻すには `echo 0 | sudo tee /sys/class/scsi_disk/0:0:0:0/manage_system_start_stop` を実行する。
次の起動時か、パーティションに change イベントが来たときに、udev ルールが再び `1` にする。
