# Bluetooth設定
{ ... }: {
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        # オーディオ関連のプロファイルを明示的に有効化
        Enable = "Source,Sink,Media,Socket";
        # 一部のイヤホンで接続を安定させる設定
        ControllerMode = "dual";
        FastConnectable = "true";
        Experimental = "true";
      };
      Policy = { AutoEnable = "true"; };
    };
  };
}
