# 目的: 自分用サーバとして、いつでも接続できるよう眠らない。外出先から起こす手段がないため、ログイン画面でもセッション内でも自動 suspend させない。
def config():
    return {"nixos": {
        "services.displayManager.gdm.autoSuspend": False,
        "services.desktopManager.gnome.extraGSettingsOverrides": "[org.gnome.settings-daemon.plugins.power]\nsleep-inactive-ac-type='nothing'\n",
    }}
