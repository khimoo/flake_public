# Claude Code のプラグイン（caveman、genshijin、ponytail、codex）はフックとコマンドを `node` で起動し、
# フックと Bash ツールは Claude Code の PATH を引き継ぐ。Node.js はシェルの PATH に入れていないので、
# Claude Code のラッパーにだけ足す。devShell の node を隠さないよう PATH の末尾に置く。
final: prev: {
  claude-code = final.symlinkJoin {
    name = "${prev.claude-code.name}-with-node";
    paths = [ prev.claude-code ];
    nativeBuildInputs = [ final.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/claude --suffix PATH : ${final.lib.makeBinPath [ final.nodejs ]}
    '';
    inherit (prev.claude-code) meta;
  };
}
