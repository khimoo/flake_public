{
  lib,
  stdenv,
  fetchurl,
  unzip,
  cmake,
  autoPatchelfHook,
  wrapGAppsHook4,
  gobject-introspection,
  fcitx5,
  icu,
  zlib,
  gtk4,
  python3,
}:

# Meltype (https://github.com/yksr-melt/Meltype) の fcitx5 版。
# 本体 (libMeltypeNative.so、.NET NativeAOT)・Mozc の変換ヘルパー・Zenzai の llama-server とモデルは
# 上流のビルド済み zip をそのまま使い、fcitx5 のアドオンだけは nixpkgs の fcitx5 に合わせて同じ版のソースからビルドする。
# 上流の zip のアドオンは Ubuntu 24.04 の fcitx5 向けで、本体の場所 /opt/meltype が埋め込まれているため。
let
  version = "1.7.1";
  raw = path: "https://raw.githubusercontent.com/yksr-melt/Meltype/v${version}/${path}";
  addonSrc = {
    cpp = fetchurl {
      url = raw "linux/fcitx5/meltype.cpp";
      sha256 = "1fn93b6maakkdai6lfpabsqp731ii7v0csvs1f67akfkh7kvhhy8";
    };
    cmake = fetchurl {
      url = raw "linux/fcitx5/CMakeLists.txt";
      sha256 = "0d586iysvw145qxn7xgwva5zrrlyngzq1733jpgcxrswj6j8xlxj";
    };
  };
  settingsPython = python3.withPackages (ps: [ ps.pygobject3 ]);
in
stdenv.mkDerivation {
  pname = "meltype";
  inherit version;

  src = fetchurl {
    url = "https://github.com/yksr-melt/Meltype/releases/download/v${version}/Meltype-${version}-linux.zip";
    sha256 = "1f7bjkna4cw3n1kii85pp86lq2f2swb520xr32sdkfpmq4a48csp";
  };
  sourceRoot = "Meltype-linux";

  nativeBuildInputs = [
    unzip
    cmake
    autoPatchelfHook
    wrapGAppsHook4
    gobject-introspection
  ];
  # stdenv.cc.cc.lib: Mozc のヘルパーと llama-server の libstdc++
  buildInputs = [
    fcitx5
    stdenv.cc.cc.lib
    zlib
    gtk4
    settingsPython
  ];

  # cmake はアドオンのビルドだけに使う (buildPhase の中で呼ぶ)
  dontUseCmakeConfigure = true;
  dontWrapGApps = true;

  buildPhase = ''
    runHook preBuild
    mkdir addon
    cp ${addonSrc.cpp} addon/meltype.cpp
    cp ${addonSrc.cmake} addon/CMakeLists.txt
    # 選んでいる文節を Wayland のアプリにも見せる (パッチの中のコメント)
    patch -d addon -p1 < ${./selected-clause-cursor.patch}
    # 端末では確定し直さない (パッチの中のコメント)
    patch -d addon -p1 < ${./terminal-no-delete.patch}
    cmake -S addon -B addon/build -DCMAKE_BUILD_TYPE=Release -DMELTYPE_DIR="$out/lib/meltype"
    cmake --build addon/build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    dir="$out/lib/meltype"
    mkdir -p "$dir"
    cp -R libMeltypeNative.so meltype-settings icon.png mozc zenzai LICENSE THIRD-PARTY-NOTICES.md "$dir/"
    chmod 755 "$dir/meltype-settings" "$dir/mozc/meltype_mozc_helper" "$dir/zenzai/llama-server"

    # fcitx5-with-addons は lib/fcitx5 と share/fcitx5 を読む
    install -Dm644 addon/build/meltype.so "$out/lib/fcitx5/meltype.so"
    install -Dm644 fcitx5/meltype-addon.conf "$out/share/fcitx5/addon/meltype.conf"
    install -Dm644 /dev/stdin "$out/share/fcitx5/inputmethod/meltype.conf" < <(sed "s|@DIR@|$dir|g" fcitx5/meltype.conf)

    mkdir -p "$out/bin" "$out/share/applications"
    ln -s "$dir/meltype-settings" "$out/bin/meltype-settings"
    sed "s|@DIR@|$dir|g" ibus-setup-meltype.desktop > "$out/share/applications/meltype-settings.desktop"
    runHook postInstall
  '';

  # 本体は ICU を dlopen で探す (無いと起動時に止まる)。dlopen は呼んだ .so の RUNPATH も見るので、ICU をそこに足す。
  postFixup = ''
    patchelf --add-rpath "${lib.getLib icu}/lib" "$out/lib/meltype/libMeltypeNative.so"
    patchShebangs "$out/lib/meltype/meltype-settings"
    substituteInPlace "$out/lib/meltype/meltype-settings" \
      --replace-quiet "#!/usr/bin/env python3" "#!${settingsPython}/bin/python3"
    wrapProgram "$out/lib/meltype/meltype-settings" "''${gappsWrapperArgs[@]}"
  '';

  meta = {
    description = "Japanese input method that tells English from romaji (fcitx5 addon)";
    homepage = "https://github.com/yksr-melt/Meltype";
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [
      binaryNativeCode
      fromSource
    ];
  };
}
