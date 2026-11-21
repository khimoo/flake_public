{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  freetype,
  fontconfig,
  libX11,
  libXext,
  libXrandr,
  libXcursor,
  libXfixes,
  libXi,
  libXScrnSaver,
  libXtst,
  libxkbcommon,
  wayland,
  libdecor,
  libGL,
  dbus,
  udev,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "ng";
  version = "0.12.0";

  # 上流の SDL3 静的リンク済みリリース。Git 取得やビルドを評価時に行わない。
  src = fetchurl {
    url = "https://github.com/Shougo/ng/releases/download/v${finalAttrs.version}/ng-v${finalAttrs.version}-linux-amd64.tar.gz";
    sha256 = "dc4f9ab62266a59ef6e2642be33e1571997b8ec08b5abfdbef793b150499407c";
  };

  nativeBuildInputs = [ autoPatchelfHook makeWrapper ];
  buildInputs = [ freetype fontconfig ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 ng "$out/bin/ng"
    install -Dm644 assets/ng.desktop "$out/share/applications/ng.desktop"
    mkdir -p "$out/share/icons"
    cp -r assets/icons/hicolor "$out/share/icons/"
    runHook postInstall
  '';

  # SDL3 は静的リンクされていても表示サーバ用ライブラリを実行時に dlopen する。
  postFixup = ''
    wrapProgram "$out/bin/ng" --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [
      libX11 libXext libXrandr libXcursor libXfixes libXi libXScrnSaver libXtst
      libxkbcommon wayland libdecor libGL dbus udev
    ]}"
  '';

  meta = {
    description = "Minimal GUI client for Neovim";
    homepage = "https://github.com/Shougo/ng";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "ng";
  };
})
