{ inputs, kiro, pkgs, lib, ... }:

let
  claude-history-pkg =
    inputs.claude-history.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # claude-history の yank は Linux では wl-copy / xclip を子プロセス起動する実装
  # (src/tui/export.rs)。これらが PATH に無いと arboard へフォールバックし、
  # Wayland では TUI 終了時にクリップボード内容が消える。
  # darwin では arboard が NSPasteboard 経由でプロセス終了後もクリップボードに
  # 残るため、ラップ不要でそのまま動く。
  claude-history-wrapped =
    if pkgs.stdenv.isLinux then
      pkgs.symlinkJoin {
        name = "claude-history-with-clipboard";
        paths = [ claude-history-pkg ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/claude-history \
            --prefix PATH : ${lib.makeBinPath [ pkgs.wl-clipboard pkgs.xclip ]}
        '';
      }
    else
      claude-history-pkg;
in
{
  home.packages = with pkgs; [
    vscode
    jetbrains.idea
    claude-code
    claude-history-wrapped
    codex
  ] ++ lib.optionals pkgs.stdenv.isLinux [
    kiro.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
