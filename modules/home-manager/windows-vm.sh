# libvirt の Windows VM を使うときだけ起動し、FreeRDP で表示する。
# 使い方は docs/howtouse/windows-vm.md、設計判断は docs/architecture/windows-vm.md。

domain=$WINDOWS_VM_DOMAIN
boot_timeout=$WINDOWS_VM_BOOT_TIMEOUT
lock=${XDG_RUNTIME_DIR:?}/windows-vm.lock
notified=

virsh() { command virsh -c qemu:///system "$@"; }

notify() { notify-send --app-name=Windows "$@" || true; }

fail() {
  notified=1
  notify "$@"
  exit 1
}

# アプリ一覧から起動すると端末がなく、エラーの出力が見えない。想定外の失敗も通知で知らせる。
on_exit() {
  local status=$?
  if [ "$status" -ne 0 ] && [ -z "$notified" ]; then
    notify "windows-vm の実行に失敗しました" "終了コード: $status。端末から windows-vm を実行すると詳細な出力を確認できます。"
  fi
}
trap on_exit EXIT

state() { virsh domstate "$domain"; }

address() {
  local proto addr
  while read -r _ _ proto addr; do
    if [ "$proto" = ipv4 ]; then
      echo "${addr%/*}"
      return
    fi
  done < <(virsh domifaddr "$domain" --source lease)
}

reachable() {
  timeout 2 "$BASH" -c ": < /dev/tcp/$1/3389" 2>/dev/null
}

# 呼び出し元の ip に、RDP が応答したアドレスを入れる。
# Windows Update の適用中は起動に数分かかるので、1 分ほどたったら一度だけ知らせる。
# 待つ間に VM が止まったら、時間切れまで待たずに知らせる（そのままではロックを握り続ける）。
wait_for_rdp() {
  local deadline=$((SECONDS + boot_timeout)) current polls=0
  until ip=$(address) && [ -n "$ip" ] && reachable "$ip"; do
    current=$(state)
    if [ "$current" != running ]; then
      fail "Windows が停止しました" "起動待機中に VM が停止しました（VM の状態: $current）"
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
      fail "Windows に接続できません" "$boot_timeout 秒待機しても RDP が応答しませんでした"
    fi
    polls=$((polls + 1))
    if [ "$polls" -eq 30 ]; then
      notify "Windows の起動に時間がかかっています" "更新プログラムを適用中の可能性があります。画面を確認するには、アプリ一覧の「Windows」を右クリックして「SPICE で開く」を選択してください。"
    fi
    sleep 2
  done
}

request_shutdown() {
  local current
  current=$(state)
  if [ "$current" != running ]; then
    notify "Windows は起動していません"
    return
  fi
  virsh shutdown "$domain" >/dev/null
  notify "Windows のシャットダウンを要求しました"
}

# GNOME の通知は一覧に残るので、古い通知のボタンがあとから押されることがある。
# そのとき別の接続が開いていれば（ロックを握れなければ）止めない。
remind() {
  local action
  action=$(notify-send --app-name=Windows --action=shutdown=シャットダウン --wait \
    "Windows はまだ起動しています" "使用を終えたらシャットダウンしてください") || return 0
  [ "$action" = shutdown ] || return 0
  exec 9>"$lock"
  if flock -n 9; then
    request_shutdown
  else
    notify "Windows を停止しませんでした" "別の接続が開いています"
  fi
}

connect() {
  local current ip polls=0
  exec 9>"$lock"
  # 同じ VM に二つ目の RDP 接続を張ると一つ目が切れるので、起動を待つ間から握っておく。
  flock -n 9 || fail "Windows は起動待機中または接続中です"
  current=$(state)
  case $current in
    running) ;;
    "shut off")
      virsh start "$domain" >/dev/null
      notify "Windows を起動しています"
      ;;
    *) fail "Windows を起動できません" "VM の状態: $current" ;;
  esac
  wait_for_rdp
  # NLA は切ってある（Entra ID のアカウントでは通らない）。TLS だけで接続し、Windows の画面でサインインする。
  sdl-freerdp "/v:$ip" /sec:tls /dynamic-resolution /network:lan +clipboard /cert:tofu || true
  flock -u 9
  exec 9>&-
  # スタートメニューからシャットダウンすると FreeRDP が先に終わり、VM はその数十秒後に止まる。
  # 止まるのを待ち、それでも動いていれば止め忘れを通知する。
  current=$(state)
  while [ "$current" = running ] && [ "$polls" -lt 30 ]; do
    sleep 2
    polls=$((polls + 1))
    current=$(state)
  done
  if [ "$current" = running ]; then remind; fi
}

case ${1-connect} in
  connect) connect ;;
  shutdown) request_shutdown ;;
  console) exec virt-manager --connect qemu:///system --show-domain-console "$domain" ;;
  *)
    notified=1
    echo "usage: windows-vm [connect|shutdown|console]" >&2
    exit 2
    ;;
esac
