# comma and the nix-index command-not-found handler share the prebuilt small
# database, which indexes bin/ only. Rationale: docs/howtouse/cli-tools/comma.md.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  nixLocate = "${config.programs.nix-index.package}/bin/nix-locate";
  # PATH に無いコマンドを handler の中で呼ぶと handler が再帰するので、道具は絶対パスで呼ぶ。
  sed = "${pkgs.gnused}/bin/sed";
  grep = "${pkgs.gnugrep}/bin/grep";
  paste = "${pkgs.coreutils}/bin/paste";

  # 対話シェルは nix-index の handler を使う。エージェントが実行する非対話の bash は .bashrc を
  # 読まないので、BASH_ENV から同じ種類の案内を定義する。取得や実行はせず、終了コードは 127 のまま。
  noninteractiveHint = pkgs.writeText "command-not-found-hint.bash" ''
    command_not_found_handle() {
      local cmd=$1 found best candidates
      printf '%s: command not found\n' "$cmd" >&2
      # nix-locate の出力を head へ直接つなぐと、閉じたパイプへの書き込みで nix-locate が落ちる。
      found=$(${nixLocate} --minimal --no-group --type x --type s --whole-name --at-root "/bin/$cmd" 2>/dev/null \
        | ${sed} -e 's/\.out$//' -e '/^tests\./d' || true)
      {
        echo "この環境は NixOS で、多くのコマンドはシステム全体には入っていない。"
        echo "プロジェクトに flake.nix や .envrc があれば、その devShell の中で実行する（nix develop / direnv）。"
        if [ -n "$found" ]; then
          best=$(printf '%s\n' "$found" | ${grep} -x -m1 -F -- "$cmd" || printf '%s\n' "$found" | ${sed} -n 1p || true)
          candidates=$( { printf '%s\n' "$best"; printf '%s\n' "$found" | ${grep} -v -x -F -- "$best"; } | ${sed} -n 1,3p | ${paste} -sd ' ' || true)
          echo "単発で使うなら: nix shell nixpkgs#$best -c $cmd ...（候補: $candidates）"
        fi
        case $cmd in
          pip | pip3) echo "Nix の Python には pip install できない。uv か devShell を使う。" ;;
        esac
      } >&2
      return 127
    }
  '';
in
{
  imports = [ inputs.nix-index-database.homeModules.nix-index ];

  programs.nix-index-database.comma.enable = lib.mkDefault true;

  programs.nix-index = {
    package = inputs.nix-index-database.packages.${pkgs.stdenv.hostPlatform.system}.nix-index-with-small-db;
    # The upstream module links the full database (about 100 MiB) into
    # ~/.cache/nix-index. Both wrappers set NIX_INDEX_DATABASE and never read it.
    symlinkToCacheHome = lib.mkDefault false;
  };

  home.sessionVariables.BASH_ENV = "${noninteractiveHint}";
}
