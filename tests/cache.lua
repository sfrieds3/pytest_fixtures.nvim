vim.opt.runtimepath:prepend(vim.fn.getcwd())
local raw
package.preload["plenary.path"] = function()
  return {
    new = function()
      return {
        read = function()
          if raw == nil then
            error("missing")
          end
          return raw
        end,
      }
    end,
  }
end
local utils = require("pytest_fixtures.utils")
local function check_empty(value)
  raw = value
  local fixtures, reason = utils.get_fixtures("cache.json", "all_fixtures")
  assert(vim.tbl_isempty(fixtures) and reason)
end
for _, value in ipairs({
  "",
  "{",
  "null",
  "42",
  "[]",
  "{}",
  '{"all_fixtures":false}',
  '{"all_fixtures":{"example":{}}}',
}) do
  check_empty(value)
end
check_empty(nil)
raw = vim.json.encode({
  all_fixtures = { example = { file_path = "conftest.py", line_number = "2" } },
  fixtures_by_test = {},
})
assert(utils.get_fixtures("cache.json", "all_fixtures").example.file_path == "conftest.py")
utils.get_current_project_and_hash = function()
  return "/example", "example"
end
utils.get_storage_path_for_project = function()
  return "cache.json"
end
assert(vim.tbl_isempty(utils.parse_fixtures_for_test("test_example.py", "test_example")))
raw = '{"fixtures_by_test":{"test_example.py":false}}'
local fixtures, reason = utils.parse_fixtures_for_test("test_example.py", "test_example")
assert(vim.tbl_isempty(fixtures) and reason)
local notices, selections = 0, 0
vim.notify = function()
  notices = notices + 1
end
utils.ui_select = function()
  selections = selections + 1
end
utils.get_current_test_info = function()
  return "test_example.py", "test_example"
end
local api = require("pytest_fixtures.api")
for _, value in ipairs({ "{", '{"all_fixtures":{},"fixtures_by_test":{}}' }) do
  raw = value
  api.all_fixtures()
  api.reverse_lookup({})
  api.goto_fixture()
end
assert(notices == 6 and selections == 0)

for _, cache in ipairs({
  { all_fixtures = { example = { file_path = "conftest.py", line_number = 1.5 } } },
  {
    all_fixtures = {
      example = {
        file_path = "conftest.py",
        line_number = 2,
        related_tests = { { path = "", name = "test_example", line = 1 } },
      },
    },
  },
}) do
  check_empty(vim.json.encode(cache))
end
raw = '{"fixtures_by_test":{"test_example.py":{"test_example":{"example":false}}}}'
fixtures, reason = utils.parse_fixtures_for_test("test_example.py", "test_example")
assert(vim.tbl_isempty(fixtures) and reason)
raw = vim.json.encode({
  fixtures_by_test = {
    ["test_example.py"] = { test_example = {
      example = { file_path = "conftest.py", line_number = 2 },
    } },
  },
})
local opened
utils.open_file_at_line = function(path, line)
  opened = { path, line }
end
utils.ui_select = function(opts)
  opts.callback(opts.items[1])
end
api.goto_fixture()
assert(opened[1] == "conftest.py" and opened[2] == 2)
print("cache checks passed")
