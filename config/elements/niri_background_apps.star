# 目的: トレイに隠れない常駐アプリ（Thunderbird と付箋）を、ログイン直後から存在する 2 番目のワークスペースへフォーカスを奪わず置く（docs/architecture/default-apps.md）。
requires = ["niri_config"]
needs = ["nixos_system"]

def writes(niri_config):
    return [write(niri_config,
        # background を先頭にすると、ログイン直後の表示がそこになる。
        workspaces = ['workspace "main"', 'workspace "background"'],
        window_rules = [
            'window-rule {\n    match app-id=r#"(?i)^(thunderbird|org[.]mozilla[.]thunderbird)$"#\n    open-on-workspace "background"\n    open-focused false\n}',
            'window-rule {\n    match app-id=r#"^com[.]vixalien[.]sticky$"#\n    open-on-workspace "background"\n    open-focused false\n}',
        ],
    )]
