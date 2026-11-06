# 設定どうしの関係（用途、動作条件、実行に必要な道具）を宣言し、実設定の生成と図の両方に使う。
# 使い方と設計判断: docs/howtouse/relations.md
{ config, lib, ... }:

let
  inherit (lib) mkOption types;
  cfg = config.local.relations;

  # Mermaid のノード ID に使えない文字を落とす。
  nodeId = prefix: name: prefix + "_" + lib.replaceStrings [ "-" "." "/" ] [ "_" "_" "_" ] name;
  label = text: ''"${lib.replaceStrings [ ''"'' ] [ "'" ] text}"'';

  purposeNodes = lib.mapAttrsToList (
    name: p: "  ${nodeId "p" name}([${label "用途: ${p.description}"}])"
  ) cfg.purposes;

  conditionNodes = lib.mapAttrsToList (
    name: c: "  ${nodeId "c" name}{${label "条件: ${c.description}"}}"
  ) cfg.conditions;

  measureNodes = lib.mapAttrsToList (
    name: m: "  ${nodeId "m" name}[${label "${m.description}<br/>${m.source}"}]"
  ) cfg.measures;

  conditionTools = lib.mapAttrsToList (name: c: {
    from = nodeId "c" name;
    tool = c.mountType.package;
  }) cfg.conditions;

  tools = lib.unique (map (e: lib.getName e.tool) conditionTools);
  toolNodes = map (n: "  ${nodeId "t" n}[(${label n})]") tools;
  toolEdges = map (e: "  ${e.from} -->|実行に必要| ${nodeId "t" (lib.getName e.tool)}") conditionTools;

  measureEdges = lib.concatLists (
    lib.mapAttrsToList (name: m: [
      "  ${nodeId "m" name} -->|用途| ${nodeId "p" m.purpose}"
      "  ${nodeId "m" name} -.->|動作条件| ${nodeId "c" m.condition}"
    ]) cfg.measures
  );
in
{
  options.local.relations = {
    purposes = mkOption {
      type = types.attrsOf (
        types.submodule {
          options.description = mkOption {
            type = types.str;
            description = "設定を何のために置くか。図のラベルになる。";
          };
        }
      );
      default = { };
      description = "対策がどの用途のためにあるか。";
    };

    conditions = mkOption {
      type = types.attrsOf (
        types.submodule (
          { config, ... }:
          {
            config.mountType.findmnt = lib.getExe' config.mountType.package "findmnt";
            options = {
              description = mkOption {
                type = types.str;
                description = "条件の説明。図のラベルになる。";
              };
              mountType = {
                fsType = mkOption {
                  type = types.str;
                  example = "fuse.sshfs";
                  description = "対象パスを含むマウントの種別がこの値のとき、条件が成り立つ。";
                };
                package = mkOption {
                  type = types.package;
                  description = "種別を調べる findmnt を含むパッケージ。";
                };
                findmnt = mkOption {
                  type = types.str;
                  readOnly = true;
                  description = "種別を調べるコマンドの絶対パス。対策の実装はこれを使う。";
                };
              };
            };
          }
        )
      );
      default = { };
      description = "対策が実行時に働く条件。";
    };

    measures = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            description = mkOption {
              type = types.str;
              description = "対策の説明。図のラベルになる。";
            };
            source = mkOption {
              type = types.str;
              description = "対策を実装しているファイル（リポジトリのルートからのパス）。";
            };
            purpose = mkOption {
              type = types.str;
              description = "local.relations.purposes の名前。";
            };
            condition = mkOption {
              type = types.str;
              description = "local.relations.conditions の名前。対策の実装はこの条件の値を使って作る。";
            };
          };
        }
      );
      default = { };
      description = "用途のために置く設定と、それが働く条件。";
    };

    mermaid = mkOption {
      type = types.str;
      readOnly = true;
      description = "このユーザー環境で宣言された関係の Mermaid 図。";
    };
  };

  config = {
    assertions = lib.concatLists (
      lib.mapAttrsToList (name: m: [
        {
          assertion = cfg.purposes ? ${m.purpose};
          message = "local.relations.measures.${name}: purpose ${m.purpose} is not declared.";
        }
        {
          assertion = cfg.conditions ? ${m.condition};
          message = "local.relations.measures.${name}: condition ${m.condition} is not declared.";
        }
      ]) cfg.measures
    );

    local.relations.mermaid =
      lib.concatStringsSep "\n" (
        [ "flowchart LR" ]
        ++ purposeNodes
        ++ conditionNodes
        ++ measureNodes
        ++ toolNodes
        ++ measureEdges
        ++ toolEdges
      )
      + "\n";
  };
}
