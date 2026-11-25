# Zen の Sine mod のうち、Sine のストアに無く flake の入力で固定するもの（config/elements/zen_browser.star が pkg("…") で指す）。
# Starlark からは flake の入力を直接指せないので、ここでパッケージの名前にする。
inputs: final: prev: {
  zen-pane-manager = inputs.zen-pane-manager;
}
