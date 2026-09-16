{ config, ... }:
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
}
