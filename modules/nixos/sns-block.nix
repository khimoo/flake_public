# SNS ブロック（自制用）
# /etc/hosts にエントリを追加し、対象ホストへのアクセスを遮断する
{
  networking.extraHosts = let
    blockedHosts = [
      "x.com"
      "www.x.com"
      "twitter.com"
      "www.twitter.com"
      # "youtube.com"
      # "www.youtube.com"
    ];
  in builtins.concatStringsSep "\n" (map (host: "0.0.0.0 ${host}") blockedHosts);
}
