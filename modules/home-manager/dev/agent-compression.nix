# 出力圧縮プラグイン (caveman / genshijin) の既定モードを宣言する。
#
# どちらも SessionStart フックで既定モードを決める。解決順は環境変数
# (<NAME>_DEFAULT_MODE) → $XDG_CONFIG_HOME/<name>/config.json の defaultMode →
# 組み込みの既定 (caveman: full, genshijin: normal)。caveman はこの間に
# repo ローカルの .caveman.json / .caveman/config.json も見る。
#
# 両方を導入すると組み込みの既定のまま二重に効くので、どちらを既定にするかを
# ここで宣言する。null なら設定ファイルを置かず、プラグイン自身の既定に任せる。
# プラグインを入れていない環境に置いても読まれないだけで害はない。
#
# 列挙しているのは常時の既定に使えるモードだけ。commit/review/compress のような
# 単発の作業モードはスラッシュコマンドで呼ぶもので、既定には置かない。
{ config, lib, ... }:
let
  cfg = config.local.agentCompression;
  modes = {
    caveman = [
      "off"
      "lite"
      "full"
      "ultra"
      "wenyan-lite"
      "wenyan"
      "wenyan-full"
      "wenyan-ultra"
    ];
    genshijin = [
      "off"
      "polite"
      "normal"
      "extreme"
    ];
  };
  mkOpt =
    name:
    lib.mkOption {
      type = lib.types.nullOr (lib.types.enum modes.${name});
      default = null;
      description = "Default mode for the ${name} output-compression plugin; null leaves the plugin's own default.";
    };
  mkFile =
    name:
    lib.mkIf (cfg.${name} != null) {
      "${name}/config.json".text = builtins.toJSON { defaultMode = cfg.${name}; } + "\n";
    };
in
{
  options.local.agentCompression = {
    caveman = mkOpt "caveman";
    genshijin = mkOpt "genshijin";
  };

  config.xdg.configFile = lib.mkMerge [
    (mkFile "caveman")
    (mkFile "genshijin")
  ];
}
