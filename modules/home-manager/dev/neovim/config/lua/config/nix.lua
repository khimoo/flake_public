-- Home Manager が生成する、有効な機能の一覧と機能ごとの値（modules/home-manager/dev/neovim）。
-- 生成物がない環境（Home Manager の適用前など）では空になり、lua/plugins/ だけを読み込む。
local path = vim.fn.stdpath("data") .. "/nix/features.lua"
local generated = vim.uv.fs_stat(path) and dofile(path) or {}

return {
  features = generated.features or {},
  data = generated.data or {},
}
