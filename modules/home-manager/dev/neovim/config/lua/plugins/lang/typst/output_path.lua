-- sshfs 上の文書だけ、tinymist の PDF 出力先を手元の tmpfs に移す。
-- 理由は docs/howtouse/neovim/lang-typst.md の「設計」にある。
-- FUSE 全体を対象にしないのは、FUSE であること自体は遅さを意味しないため。

local M = {}

---@param dir string
---@return boolean
local function on_sshfs(dir)
  local result = vim.system({ "findmnt", "-n", "-o", "FSTYPE", "-T", dir }, { text = true }):wait()
  return result.code == 0 and vim.trim(result.stdout) == "fuse.sshfs"
end

---@param root string tinymist のプロジェクトルート
---@return string|nil tinymist の outputPath。sshfs 上でなければ nil
function M.resolve(root)
  local runtime = vim.env.XDG_RUNTIME_DIR
  if not runtime or not on_sshfs(root) then
    return nil
  end
  return runtime .. "/typst-out/" .. vim.fs.basename(root) .. "/$dir/$name"
end

return M
