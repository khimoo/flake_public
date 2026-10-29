{ lib, buildNpmPackage, nodejs_24, makeWrapper, autoPatchelfHook, stdenv }:

let
  version = (lib.importJSON ./package.json).dependencies."@alook/app";
in
buildNpmPackage {
  pname = "alook";
  inherit version;
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [ ./package.json ./package-lock.json ];
  };
  nodejs = nodejs_24;
  npmDepsHash = "sha256-zqTtdwxXW8crSaiYtrQTox0lXV8vXNO1lEFJOJxHQKE=";
  dontNpmBuild = true;
  npmRebuildFlags = [ "--ignore-scripts" ];
  dontStrip = true;

  nativeBuildInputs = [ makeWrapper autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];

  # patchelf 0.15.2 は libvips の実行セクションを壊すため、それ以外の ELF だけを修正する。
  dontAutoPatchelf = true;
  postFixup = ''
    addAutoPatchelfSearchPath "$out/lib"
    mapfile -d $'\0' alookElfCandidates < <(
      find "$out" -type f ! -name 'libvips-cpp.so.*' \
        \( -name '*.node' -o -name '*.so*' -o -executable \) -print0
    )
    autoPatchelf --no-recurse "''${alookElfCandidates[@]}"
  '';

  installPhase = ''
    runHook preInstall
    patch --fuzz=0 -p1 -d node_modules/@alook/app < ${./writable-install.patch}
    find node_modules -type d \( -name '*-musl' -o -name '*-linuxmusl-*' \) \
      -prune -exec rm -rf {} +
    mkdir -p "$out/lib/alook" "$out/bin"
    cp -r node_modules "$out/lib/alook/"
    makeWrapper ${nodejs_24}/bin/node "$out/bin/alook-app" \
      --add-flags "$out/lib/alook/node_modules/@alook/app/dist/index.js" \
      --prefix PATH : ${lib.makeBinPath [ nodejs_24 ]}
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME="$TMPDIR/alook-check"
    mkdir -p "$HOME"
    test "$("$out/bin/alook-app" --version)" = '${version}'
    "$out/bin/alook-app" daemon list --json
    cd "$out/lib/alook"
    node - <<'JS'
    const assert = require('node:assert/strict');
    const { execFileSync } = require('node:child_process');
    (async () => {
      const data = await require('sharp')({create: {width: 2, height: 2, channels: 3, background: 'red'}})
        .png().toBuffer();
      assert.equal(data.subarray(0, 8).toString('hex'), '89504e470d0a1a0a');
      const { getQuickJS } = require('quickjs-emscripten');
      const context = (await getQuickJS()).newContext();
      try {
        const value = context.unwrapResult(context.evalCode('1 + 2'));
        assert.equal(context.dump(value), 3);
        value.dispose();
      } finally {
        context.dispose();
      }
      assert.match(require('esbuild').transformSync('const value: number = 3', {loader: 'ts'}).code, /const value = 3/);
      assert.match(execFileSync(require('workerd').default, ['--version'], {encoding: 'utf8'}), /^workerd /);
      console.log('PNG encoding, QuickJS, esbuild, and workerd: OK');
    })().catch(error => { console.error(error); process.exit(1); });
    JS
    runHook postInstallCheck
  '';

  meta = {
    description = "Local Alook web app and agent collaboration server";
    homepage = "https://github.com/alookai/alook";
    license = lib.licenses.asl20;
    mainProgram = "alook-app";
    platforms = [ "x86_64-linux" ];
  };
}
