{ pkgs, ... }:

{
  programs.yazi = {
    enable = true;
    enableBashIntegration = true;

    plugins = {
      inherit (pkgs.yaziPlugins)
        smart-enter # Enter でファイルを開く / ディレクトリに入る
        full-border # 全体に枠線を表示して見やすくする
        smart-filter # インクリメンタルフィルタ (一意なら自動で入る)
        chmod # 選択ファイルのパーミッション変更
        git # Git の変更状態を linemode に表示
        jump-to-char # Vim の f<char> のように名前先頭文字でジャンプ
        ;
    };

    # init.lua — プラグインの初期化
    initLua = ./yazi-init.lua;

    keymap = {
      manager.prepend_keymap = [
        # smart-enter: Enter でディレクトリなら移動、ファイルなら開く
        {
          on = "<Enter>";
          run = "plugin smart-enter";
          desc = "Enter the child directory, or open the file";
        }
        # smart-filter: F でインクリメンタルフィルタ開始
        #   入力中にリアルタイム絞り込み、候補が1つなら自動で入る
        {
          on = "F";
          run = "plugin smart-filter";
          desc = "Smart filter";
        }
        # jump-to-char: f でファイル名の先頭文字ジャンプ (Vim の f と同じ感覚)
        {
          on = "f";
          run = "plugin jump-to-char";
          desc = "Jump to char";
        }
        # chmod: cm で選択ファイルのパーミッションを変更
        #   実行後に rwx のトグル UI が表示される
        {
          on = [
            "c"
            "m"
          ];
          run = "plugin chmod";
          desc = "Chmod on selected files";
        }
      ];
    };

    settings = {
      manager = {
        show_hidden = true;
        sort_by = "natural";
        sort_dir_first = true;
      };

      # git.yazi: ファイル一覧取得時に Git 状態を自動フェッチ
      plugin.prepend_fetchers = [
        {
          id = "git";
          name = "*";
          run = "git";
        }
        {
          id = "git";
          name = "*/";
          run = "git";
        }
      ];
    };
  };
}
