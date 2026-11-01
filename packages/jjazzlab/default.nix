{ lib, stdenvNoCC, fetchurl, jdk25, fluidsynth, makeDesktopItem, copyDesktopItems }:

# 配布物は NetBeans Platform のアプリで、nixpkgs には無い。
# バージョンの上げ方と、同梱の JRE を使わない理由は docs/howtouse/jjazzlab.md に書く。
let
  version = "5.2.1";

  icon = fetchurl {
    url = "https://raw.githubusercontent.com/jjazzboss/JJazzLab/${version}/graphics/logo-JJazzLab.svg";
    hash = "sha256-aTKN9M//4lMx5YryhP+nMgz5nNJCWCwgaP2GNxEd9aw=";
  };

  # 内蔵シンセの Java バインディングは FluidSynth 2.3 のヘッダから生成されているので、
  # ABI が同じ soname 3 を指す。soname が変わったら installCheck で build を止める。
  libfluidsynth = "${lib.getLib fluidsynth}/lib/libfluidsynth.so.3";
in
stdenvNoCC.mkDerivation {
  pname = "jjazzlab";
  inherit version;

  src = fetchurl {
    url = "https://github.com/jjazzboss/JJazzLab/releases/download/${version}/JJazzLab-${version}-linux-x64.tar.xz";
    hash = "sha256-u5XKXxjJ+hdeWnAAL6bDhy7RrriIdNY+p9ScvJL7KYs=";
  };

  nativeBuildInputs = [ copyDesktopItems ];

  desktopItems = [
    (makeDesktopItem {
      name = "org.jjazzlab.JJazzLab";
      desktopName = "JJazzLab";
      comment = "Generate backing tracks for any song";
      icon = "org.jjazzlab.JJazzLab";
      exec = "jjazzlab";
      categories = [ "AudioVideo" "Audio" "Midi" "Music" ];
      # JJazzLab はウィンドウをスレッドから開くので、AWT は WM_CLASS を
      # java.lang.Thread のクラス名から作る。GNOME はこの値でウィンドウとランチャーを結び付ける。
      startupWMClass = "java-lang-Thread";
    })
  ];

  installPhase = ''
    runHook preInstall

    rm -r jdk
    # 内蔵シンセのローダーは FHS の /usr/lib などしか探さないので、
    # 起動オプションの fluidsynthlib.path でライブラリの場所を渡す。
    substituteInPlace etc/jjazzlab.conf \
      --replace-fail 'jdkhome="jdk"' 'jdkhome="${jdk25.home}"' \
      --replace-fail 'default_options="' 'default_options="-J-Dfluidsynthlib.path=${libfluidsynth} '

    mkdir -p "$out/share/jjazzlab" "$out/bin"
    cp -r . "$out/share/jjazzlab/"
    ln -s "$out/share/jjazzlab/bin/jjazzlab" "$out/bin/jjazzlab"
    install -Dm644 ${icon} "$out/share/icons/hicolor/scalable/apps/org.jjazzlab.JJazzLab.svg"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -e ${libfluidsynth}
    runHook postInstallCheck
  '';

  meta = {
    description = "Backing track generator for any song";
    homepage = "https://www.jjazzlab.org/";
    license = lib.licenses.lgpl21Only;
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "jjazzlab";
  };
}
