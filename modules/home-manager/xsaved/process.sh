# frames は何日も GPU のロックを持つので、止めないと新しいツイートの計算が待ち続ける。
systemctl --user stop xsaved-frames.service
status=0
xsaved embed text || status=1
xsaved ocr || status=1
xsaved embed images || status=1
xsaved tag || status=1
xsaved tag-names || status=1
xsaved embed text || status=1
systemctl --user start --no-block xsaved-frames.service
exit "$status"
