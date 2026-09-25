{ config, lib, pkgs, ... }:
{
  local.profile = {
    gitUsername = "khimoo";
    gitUserEmail = "dailysentence1111@gmail.com";
    # 日本語の校正を Gemini へ投げるときに使う。無料枠のキーで課金プロジェクトは
    # 紐づけていないので、漏れても被害は無料枠の消費に留まる。使う側は
    # agents-private の shared/skills/gemini-proofread。
    secrets = [
      {
        secret = "gemini_api_key";
        path = "${config.home.homeDirectory}/.config/gemini/api-key";
      }
    ];
  };

  # gemini-proofread が Gemini の API で校正できないときの予備の経路。
  # 版を固定しているのは x86_64-linux の配布物だけなので、macOS には入れない。
  home.packages = lib.optionals (pkgs.stdenv.hostPlatform.system == "x86_64-linux") [
    (pkgs.callPackage ../../packages/antigravity-cli { })
  ];
}
