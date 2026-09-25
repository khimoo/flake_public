{ lib, stdenv, fetchurl, autoPatchelfHook }:

# 配布物は glibc に動的リンクした単体バイナリで、nixpkgs には無い（nixpkgs#antigravity は IDE）。
# 版は公式マニフェストの URL と sha512 で固定する。agy の自己更新は Nix store に書き込めず
# 働かないので、版の上げ方は docs/howtouse/cli-tools/antigravity-cli.md に従う。
stdenv.mkDerivation rec {
  pname = "antigravity-cli";
  version = "1.2.10";

  src = fetchurl {
    url = "https://storage.googleapis.com/antigravity-public/antigravity-cli/1.2.10-4751581200121856/linux-x64/cli_linux_x64.tar.gz";
    sha512 = "e19aef599aaf47a9225e72f2cd420d5f97d6dd974e698685950557ca23a8bda63effe666773178c82912b98e9c197da29829b92e771eb6f66c82236f17864fee";
  };
  sourceRoot = ".";

  nativeBuildInputs = [ autoPatchelfHook ];
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 antigravity "$out/bin/agy"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test "$(HOME="$TMPDIR" "$out/bin/agy" --version)" = '${version}'
    runHook postInstallCheck
  '';

  meta = {
    description = "Google Antigravity CLI (agy)";
    homepage = "https://antigravity.google/docs/cli/install/";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "agy";
  };
}
