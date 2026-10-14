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
    notify "windows-vm が失敗しました" "終了コード $status。端末から windows-vm を実行すると出力を確認できます。"
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

wait_for_rdp() {
  local deadline=$((SECONDS + boot_timeout)) ip
  until ip=$(address) && [ -n "$ip" ] && reachable "$ip"; do
    if [ "$SECONDS" -ge "$deadline" ]; then return 1; fi
    sleep 2
  done
  echo "$ip"
}

request_shutdown() {
  if [ "$(state)" != running ]; then
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
    "Windows はまだ起動しています" "使い終わったらシャットダウンしてください") || return 0
  [ "$action" = shutdown ] || return 0
  exec 9>"$lock"
  if flock -n 9; then
    request_shutdown
  else
    notify "Windows を止めませんでした" "別の接続が開いています"
  fi
}

connect() {
  local current ip
  exec 9>"$lock"
  # 同じ VM に二つ目の RDP 接続を張ると一つ目が切れるので、起動を待つ間から握っておく。
  flock -n 9 || fail "Windows への接続はすでに開いています"
  current=$(state)
  case $current in
    running) ;;
    "shut off")
      virsh start "$domain" >/dev/null
      notify "Windows を起動しています"
      ;;
    *) fail "Windows を起動できません" "VM の状態: $current" ;;
  esac
  ip=$(wait_for_rdp) || fail "Windows に接続できません" "$boot_timeout 秒待っても RDP が応答しませんでした"
  # NLA は切ってある（Entra ID のアカウントでは通らない）。TLS だけで接続し、Windows の画面でサインインする。
  sdl-freerdp "/v:$ip" /sec:tls /dynamic-resolution /network:lan +clipboard /cert:tofu || true
  flock -u 9
  exec 9>&-
  if [ "$(state)" = running ]; then remind; fi
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
