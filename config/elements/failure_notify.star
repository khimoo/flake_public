def public():
    return {"on_failure": ["notify-failure@%n.service"]}

def config(host):
    if not host.linux:
        return {}
    notify = script("notify-failure", concat("unit=$1\n# 同じユニットが失敗を繰り返しても通知が積み重ならないよう、前回の通知を置き換える。\n# 閉じた通知の ID を渡したときは、新しい通知になる。\nids=\"$XDG_RUNTIME_DIR/notify-failure\"\nmkdir -p \"$ids\"\nid=$(cat \"$ids/$unit\" 2>/dev/null) || id=0\nid=$(", exe("libnotify", "notify-send"), " --urgency=critical --app-name=systemd --print-id --replace-id=\"$id\" \\\n  \"$unit が失敗しました\" \"journalctl --user -u $unit で原因を確かめる\") &&\n  printf '%s\\n' \"$id\" > \"$ids/$unit\"\n"))
    return {"home": {"systemd.user.services.notify-failure@": {
        "Unit": {"Description": "%i の失敗をデスクトップに通知する"},
        "Service": {"Type": "oneshot", "ExecStart": concat(notify, " %i")},
    }}}
