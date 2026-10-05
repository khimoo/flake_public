# GNOME 50 の表示更新と AEC の内部ストリームの除外に必要な修正。
# 上流に同等修正と GNOME 50 対応が入ったら再評価する。
# 設計判断: docs/architecture/audio-echo-cancel.md
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  glib,
  jq,
  nodejs,
  pulseaudio,
}:
let
  extensionUuid = "mic-indicator-visibility-manager@alhaddar.dev";
in
stdenvNoCC.mkDerivation {
  pname = "mic-indicator-visibility-manager";
  version = "1-unstable-732eb61";

  src = fetchFromGitHub {
    owner = "moalhaddar";
    repo = "mic-indicator-visibilty-manager";
    rev = "732eb61c452025b80a0a5c1943fbec86137a05d8";
    hash = "sha256-ugowqcNU2+5litIQBoycaxQkypQE6UMjLE0QVKXXWtk=";
  };

  nativeBuildInputs = [ glib jq nodejs ];
  dontConfigure = true;
  dontBuild = true;

  postPatch = ''
    cp ${./extension.js} extension.js
    cp ${./filter.js} filter.js
    cp ${./test.mjs} test.mjs
    substituteInPlace extension.js \
      --replace-fail '@pactl@' '${lib.getExe' pulseaudio "pactl"}'
    jq '."shell-version" = ["50"]' metadata.json > metadata.json.tmp
    mv metadata.json.tmp metadata.json
  '';

  installPhase = ''
    runHook preInstall
    extensionDir="$out/share/gnome-shell/extensions/${extensionUuid}"
    mkdir -p "$extensionDir"
    cp extension.js filter.js prefs.js metadata.json "$extensionDir/"
    cp -r schemas "$extensionDir/"
    rm -f "$extensionDir/schemas/gschemas.compiled"
    glib-compile-schemas "$extensionDir/schemas"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    node ./test.mjs
    extensionDir="$out/share/gnome-shell/extensions/${extensionUuid}"
    test -f "$extensionDir/metadata.json"
    jq -e '.uuid == "${extensionUuid}" and ."shell-version" == ["50"]' \
      "$extensionDir/metadata.json"
    test -s "$extensionDir/schemas/gschemas.compiled"
    runHook postInstallCheck
  '';

  passthru.extensionUuid = extensionUuid;

  meta = {
    description = "GNOME microphone indicator filtering for internal echo-cancel streams";
    homepage = "https://github.com/moalhaddar/mic-indicator-visibilty-manager";
    # 上流に LICENSE がないため、ライセンスを推定して設定しない。
    platforms = lib.platforms.linux;
  };
}
