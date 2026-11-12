{ twindesk, nodejs }:
twindesk.overrideAttrs (old: {
  postInstall = (old.postInstall or "") + ''
    cp -r shared/web shared/airplay "$out/share/twindesk/shared/"
    cp -r web "$out/share/twindesk/web"
    cp -r android/app/src/main/assets/web "$out/share/twindesk/android-web"
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = (old.nativeInstallCheckInputs or [ ]) ++ [ nodejs ];
  installCheckPhase = ''
    runHook preInstallCheck
    node -e "require.resolve('$out/share/twindesk/shared/web/webwire.js')"
    test -s "$out/share/twindesk/web/index.html"
    test -s "$out/share/twindesk/android-web/viewer.html"
    test -s "$out/share/twindesk/linux/vendor/scrcpy-server"
    runHook postInstallCheck
  '';
})
