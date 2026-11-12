def user_config():
    return {"home": {
        "programs.yazi.enable": True,
        "programs.yazi.enableBashIntegration": True,
        # home.stateVersion が 26.05 未満のあいだ、Home Manager は従来の既定（yy）を使うので明示する。
        # 全ユーザーの home.stateVersion が 26.05 以上になったら既定と同じになるので、この行を消す。
        "programs.yazi.shellWrapperName": "y",
        "programs.yazi.plugins": {
            "smart-enter": pkg("yaziPlugins.smart-enter"),  # Enter でファイルを開く / ディレクトリに入る
            "full-border": pkg("yaziPlugins.full-border"),  # 全体に枠線を表示する
            "smart-filter": pkg("yaziPlugins.smart-filter"),  # インクリメンタルフィルタ（一意なら自動で入る）
            "chmod": pkg("yaziPlugins.chmod"),  # 選択ファイルのパーミッション変更
            "git": pkg("yaziPlugins.git"),  # Git の変更状態を linemode に表示
            "jump-to-char": pkg("yaziPlugins.jump-to-char"),  # Vim の f<char> のように名前の先頭文字へ飛ぶ
        },
        "programs.yazi.initLua": """-- full-border: 全体に枠線を表示
require("full-border"):setup()

-- git: ファイル一覧に Git 状態を表示
require("git"):setup()
""",
        "programs.yazi.keymap.manager.prepend_keymap": [
            {"on": "<Enter>", "run": "plugin smart-enter", "desc": "Enter the child directory, or open the file"},
            # 入力中にリアルタイムで絞り込み、候補が1つなら自動で入る。
            {"on": "F", "run": "plugin smart-filter", "desc": "Smart filter"},
            {"on": "f", "run": "plugin jump-to-char", "desc": "Jump to char"},
            # 実行後に rwx のトグル UI が表示される。
            {"on": ["c", "m"], "run": "plugin chmod", "desc": "Chmod on selected files"},
        ],
        "programs.yazi.settings": {
            "manager": {"show_hidden": True, "sort_by": "natural", "sort_dir_first": True},
            # git.yazi: ファイル一覧の取得時に Git の状態を取る。
            "plugin": {"prepend_fetchers": [
                {"group": "git", "url": "*", "run": "git"},
                {"group": "git", "url": "*/", "run": "git"},
            ]},
        },
    }}
