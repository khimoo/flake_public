# 目的: 自分用サーバとして、いつでも接続できるよう眠らない。外出先から起こす手段がないため、ログイン画面でもセッション内でも自動 suspend させない。
def config():
    return {"nixos": {"services.displayManager.gdm.autoSuspend": False}}

# 画面のロックと消灯は残し、swayidle の自動 suspend だけを外す。
def writes(swayidle):
    return [write(swayidle, disable_suspend = True)]
