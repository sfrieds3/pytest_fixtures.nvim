vim.opt.runtimepath:prepend(vim.fn.getcwd())
local utils = require("pytest_fixtures.utils")
local root = "/example/project"
local calls = {}
local callback
utils.get_project_root = function()
  return root
end
utils.has_pytest = function()
  return true
end
utils.ensure_data_path_exists = function() end
utils.parse_and_store_project_fixtures = function()
  calls.stored = true
end
local notifications = {}
vim.notify = function(message)
  table.insert(notifications, message)
end
local function system(command, opts, on_exit)
  calls.command = command
  calls.cwd = opts.cwd
  callback = on_exit
end
vim.system = system

utils.maybe_refresh_pytest_fixture_cache("/example/project/helpers.py")
assert(not utils.refreshing, "non-test file must not lock refresh")
utils.maybe_refresh_pytest_fixture_cache("/example/project/test_example.py")
assert(utils.refreshing, "refresh must stay locked while pytest runs")
assert(calls.cwd == root, "pytest must run from the project root")
assert(calls.command[1] == "pytest", "pytest must resolve through inherited PATH")
local first_callback = callback
utils.maybe_refresh_pytest_fixture_cache("/example/project/test_other.py")
assert(callback == first_callback, "overlapping refresh must be skipped")
callback({ code = 0, stdout = "", stderr = "" })
vim.wait(1000, function()
  return not utils.refreshing
end)
assert(calls.stored, "successful output must be stored")
calls.stored = false
utils.maybe_refresh_pytest_fixture_cache("example_test.py")
assert(utils.refreshing, "pytest suffix convention must be supported")
callback({ code = 1, stdout = "", stderr = "collection failed" })
vim.wait(1000, function()
  return not utils.refreshing
end)
assert(not calls.stored, "failed collection must preserve cached fixtures")
utils.maybe_refresh_pytest_fixture_cache("helpers.py", { force = true })
assert(utils.refreshing, "forced refresh must bypass the test filename filter")
callback({ code = 0, stdout = "", stderr = "" })
assert(vim.wait(1000, function()
  return not utils.refreshing
end))
utils.has_pytest = function()
  return false
end
utils.maybe_refresh_pytest_fixture_cache("test_example.py")
assert(not utils.refreshing, "missing executable must not lock refresh")
utils.has_pytest = function()
  return true
end
utils.parse_and_store_project_fixtures = function()
  error("invalid output")
end
utils.maybe_refresh_pytest_fixture_cache("test_example.py")
callback({ code = 0, stdout = "invalid", stderr = "" })
assert(vim.wait(1000, function()
  return not utils.refreshing
end))
assert(notifications[#notifications]:match("Could not parse"), "parse errors must produce feedback")
vim.system = function()
  error("spawn failed")
end
utils.maybe_refresh_pytest_fixture_cache("test_example.py")
assert(not utils.refreshing, "spawn failure must release refresh lock")
assert(notifications[#notifications]:match("Could not start"), "spawn errors must produce feedback")
root = nil
utils.maybe_refresh_pytest_fixture_cache("test_example.py")
assert(not utils.refreshing, "missing project root must not lock refresh")
print("refresh regression checks passed")
