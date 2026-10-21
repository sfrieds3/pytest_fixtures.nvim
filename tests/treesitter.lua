vim.opt.runtimepath:prepend(vim.fn.getcwd())
local utils = require("pytest_fixtures.utils")
utils.get_project_root = function()
  return "/tmp"
end
vim.api.nvim_buf_set_name(0, "/tmp/generic-project/test_example.py")
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
  "def test_example(client, typed: str, default=1, typed_default: str = 'x'):",
  "    assert client",
  "",
  "class TestExample:",
  "    def test_example(self, other):",
  "        assert other",
  "",
  "def helper():",
  "    pass",
})
vim.bo.filetype = "python"
-- Fail explicitly if a real parser is unavailable; do not silently skip coverage.
assert(vim.treesitter.get_parser(0, "python"))
package.preload["nvim-treesitter.ts_utils"] = function()
  error("legacy dependency must not be loaded")
end
local function check(row, expected_name, expected_args)
  vim.api.nvim_win_set_cursor(0, { row, 4 })
  assert(utils.get_parent_test_function() == expected_name)
  local file, name, args = utils.get_current_test_info()
  assert(name == expected_name)
  if name then
    assert(file == "generic-project/test_example.py")
    assert(vim.deep_equal(args, expected_args), vim.inspect(args))
  else
    assert(file == nil and args == nil)
  end
end
check(2, "test_example", { "client", "typed", "default", "typed_default" })
check(6, "test_example", { "self", "other" })
check(9, nil)
local get_parser = vim.treesitter.get_parser
for _, replacement in ipairs({
  function()
    error("parser unavailable")
  end,
  function()
    return nil
  end,
  function()
    return {
      parse = function()
        return {}
      end,
    }
  end,
  function()
    return {
      parse = function()
        error("parse failed")
      end,
    }
  end,
}) do
  vim.treesitter.get_parser = replacement
  check(2, nil)
end
vim.treesitter.get_parser = get_parser
local get_node = vim.treesitter.get_node
vim.treesitter.get_node = function()
  error("tree unavailable")
end
check(2, nil)
vim.treesitter.get_node = get_node
print("Tree-sitter regression checks passed")
