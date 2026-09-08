{ lib, buildNpmPackage, nodejs_24, makeWrapper, autoPatchelfHook, stdenv, openssl, zlib }:

# npm の配布物と全依存を package-lock.json / npmDepsHash で固定する。
# nixpkgs-unstable の happy-coder は 0.11.2 のため、現行 CLI をここで管理する。
buildNpmPackage {
  pname = "happy-coder";
  version = "1.2.3";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [ ./package.json ./package-lock.json ];
  };
  nodejs = nodejs_24;
  npmDepsHash = "sha256-xl3XEPXXzBBjnErPOfoyFGhHubD2VhPBvyI3kgp2pac=";
  dontNpmBuild = true;
  npmRebuildFlags = [ "--ignore-scripts" ];

  nativeBuildInputs = [ makeWrapper ] ++ lib.optionals stdenv.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.isLinux [ stdenv.cc.cc.lib openssl zlib ];

  # patchelf 0.15.2 はこの libvips の .init/.plt を実行権のない LOAD に移し、
  # sharp の import で SIGSEGV を起こす。libvips は未加工のままで Node の
  # ライブラリでロードできるので、他の ELF だけを修正する。
  dontAutoPatchelf = true;
  postFixup = lib.optionalString stdenv.isLinux ''
    addAutoPatchelfSearchPath "$out/lib"
    mapfile -d $'\0' happyElfCandidates < <(
      find "$out" -type f ! -name 'libvips-cpp.so.*' \
        \( -name '*.node' -o -name '*.so*' -o -executable \) -print0
    )
    autoPatchelf --no-recurse "''${happyElfCandidates[@]}"
  '';

  installPhase = ''
    runHook preInstall
    # 1.2.3 は --version の表示後にもログイン・Claude 起動へ進んでしまう。
    # 表示だけで終了するようにする（上流で直ったら削除）。
    substituteInPlace node_modules/happy/dist/index-K72yHyB6.mjs \
      --replace-fail 'console.log(`happy version: ''${packageJson.version}`);' \
                     'console.log(`happy version: ''${packageJson.version}`); return;'
    # 上流 postinstall は同梱アーカイブの展開のみ。ネットワーク不要。
    node node_modules/happy/scripts/unpack-tools.cjs
    ${lib.optionalString stdenv.isLinux ''
      # npm は glibc / musl の両方を展開する。glibc 向けのパッケージだけを残す。
      find node_modules -type d \( -name '*-musl' -o -name '*-linuxmusl-*' \) \
        -prune -exec rm -rf {} +
    ''}
    mkdir -p "$out/lib/happy" "$out/bin"
    cp -r node_modules "$out/lib/happy/"
    for program in happy happy-mcp; do
      makeWrapper ${nodejs_24}/bin/node "$out/bin/$program" \
        --add-flags "$out/lib/happy/node_modules/happy/bin/$program.mjs" \
        --prefix PATH : ${lib.makeBinPath [ nodejs_24 ]}
    done
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    versionOutput=$(HAPPY_HOME_DIR="$TMPDIR/happy-check" "$out/bin/happy" --version)
    test "$versionOutput" = 'happy version: 1.2.3'
    # --version では読み込まれない画像処理 / PTY / DB のネイティブ依存も確認。
    cd "$out/lib/happy"
    node - <<'JS'
    const assert = require('node:assert/strict');
    require('@lydell/node-pty');
    require('@libsql/client');
    require('sharp')({create: {width: 2, height: 2, channels: 3, background: 'red'}})
      .png().toBuffer().then(data => {
        assert.equal(data.subarray(0, 8).toString('hex'), '89504e470d0a1a0a');
        console.log('Native modules and PNG encoding: OK');
      }).catch(error => { console.error(error); process.exit(1); });
    JS
    runHook postInstallCheck
  '';

  meta = {
    description = "Mobile and web client for Codex and Claude Code";
    homepage = "https://github.com/slopus/happy";
    license = lib.licenses.mit;
    mainProgram = "happy";
    platforms = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
  };
}
