# comma と nix-index の command-not-found の handler は、bin/ だけを索引した小さいデータベースを
# 共有する。理由: docs/howtouse/cli-tools/comma.md
_DB = inputPkg("nix-index-database", "nix-index-with-small-db")

def config():
    locate = concat(_DB, "/bin/nix-locate")
    # PATH に無いコマンドを handler の中で呼ぶと handler が再帰するので、道具は絶対パスで呼ぶ。
    sed = exe("gnused", "sed")
    grep = exe("gnugrep", "grep")
    paste = exe("coreutils", "paste")
    # 対話シェルは nix-index の handler を使う。エージェントが実行する非対話の bash は .bashrc を
    # 読まないので、BASH_ENV から同じ種類の案内を定義する。取得や実行はせず、終了コードは 127 のまま。
    hint = file("command-not-found-hint.bash", concat(
        """command_not_found_handle() {
  local cmd=$1 found best candidates
  printf '%s: command not found\\n' "$cmd" >&2
  # nix-locate の出力を head へ直接つなぐと、閉じたパイプへの書き込みで nix-locate が落ちる。
  found=$(""", locate, """ --minimal --no-group --type x --type s --whole-name --at-root "/bin/$cmd" 2>/dev/null \\
    | """, sed, """ -e 's/\\.out$//' -e '/^tests\\./d' || true)
  {
    echo "この環境は NixOS で、多くのコマンドはシステム全体には入っていない。"
    echo "プロジェクトに flake.nix や .envrc があれば、その devShell の中で実行する（nix develop / direnv）。"
    if [ -n "$found" ]; then
      best=$(printf '%s\\n' "$found" | """, grep, """ -x -m1 -F -- "$cmd" || printf '%s\\n' "$found" | """, sed, """ -n 1p || true)
      candidates=$( { printf '%s\\n' "$best"; printf '%s\\n' "$found" | """, grep, """ -v -x -F -- "$best"; } | """, sed, """ -n 1,3p | """, paste, """ -sd ' ' || true)
      echo "単発で使うなら: nix shell nixpkgs#$best -c $cmd ...（候補: $candidates）"
    fi
    case $cmd in
      pip | pip3) echo "Nix の Python には pip install できない。uv か devShell を使う。" ;;
    esac
  } >&2
  return 127
}
""",
    ))
    return {
        "home_imports": [module("nix-index-database", "homeModules.nix-index")],
        "home": {
            "programs.nix-index-database.comma.enable": True,
            "programs.nix-index.package": _DB,
            # 上流のモジュールは全体のデータベース（約 100 MiB）を ~/.cache/nix-index に置く。
            # 2つのラッパーはどちらも NIX_INDEX_DATABASE を設定し、そこを読まない。
            "programs.nix-index.symlinkToCacheHome": False,
            "home.sessionVariables.BASH_ENV": concat(hint),
        },
    }
