# 目的: ローカルの AI 協業掲示板を運用する。ほかの端末からは SSH で接続する。
requires = ["expose_services", "hermes_agent"]
needs = ["nixos_system"]
role = True

def user_config():
    return {"home_imports": [repoModule("modules/home-manager/aiboard/default.nix")]}
