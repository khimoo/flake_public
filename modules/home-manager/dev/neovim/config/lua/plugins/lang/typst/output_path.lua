-- sshfs 上の文書だけ、tinymist の PDF 出力先を手元の tmpfs に移す。
-- 理由は docs/howtouse/neovim/lang-typst.md の「設計」にある。
-- 判定に使う種別とコマンドは config/elements/sshfs_editing.star が Nix 経由で渡す。
-- ここに "findmnt" や "fuse.sshfs" を直接書くと、参照を通らない依存になる。

local M = {}

---@param dir string
---@param condition { findmnt: string, fsType: string }
---@return boolean
local function on_mount_type(dir, condition)
  local result = vim.system({ condition.findmnt, "-n", "-o", "FSTYPE", "-T", dir }, { text = true }):wait()
  return result.code == 0 and vim.trim(result.stdout) == condition.fsType
end

---@param root string tinymist のプロジェクトルート
---@return string|nil tinymist の outputPath。条件に当てはまらなければ nil
function M.resolve(root)
  local condition = (require("config.nix").data.lsp or {}).tinymistOutput
  local runtime = vim.env.XDG_RUNTIME_DIR
  if not condition or not runtime or not on_mount_type(root, condition) then
    return nil
  end
  return runtime .. "/typst-out/" .. vim.fs.basename(root) .. "/$dir/$name"
end

return M
