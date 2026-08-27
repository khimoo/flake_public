-- 分割された Typst 文書の起点ファイルを求める。
-- tinymist は既定で開いているバッファ自身をエントリポイントとするため、
-- #include される側を編集すると root 側の show rule や他ファイルのラベルが解決されない。
-- 起点をファイル名で設定に書くと文書ごとに書き換えが要るので、
-- 参照関係を辿って求める。

local M = {}

---@param path string
---@return string|nil 同ディレクトリで path を #include / #import しているファイル
local function find_referrer(path)
  local dir = vim.fs.dirname(path)
  local name = vim.fn.fnamemodify(path, ":t")

  for entry, kind in vim.fs.dir(dir) do
    local candidate = dir .. "/" .. entry
    if kind == "file" and entry:sub(-4) == ".typ" and candidate ~= path then
      local ok, lines = pcall(vim.fn.readfile, candidate)
      if ok then
        for _, line in ipairs(lines) do
          local directive = line:find("#include", 1, true) or line:find("#import", 1, true)
          if directive and line:find(name, 1, true) then
            return candidate
          end
        end
      end
    end
  end
end

---参照元を辿れなくなるまで遡る。誰からも参照されないファイルは自分自身が起点。
---@param path string
---@return string
function M.resolve(path)
  local current = vim.fn.fnamemodify(path, ":p")
  local seen = { [current] = true }

  while true do
    local referrer = find_referrer(current)
    if not referrer or seen[referrer] then
      return current
    end
    seen[referrer] = true
    current = referrer
  end
end

return M
