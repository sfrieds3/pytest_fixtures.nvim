local M = {}
local Path = require("plenary.path")
local Job = require("plenary.job")
local TSUtils = require("nvim-treesitter.ts_utils")

M.debug = false

--- Get project root for a given file based on configured project_markers
---@param file string filename for which to find root directory
---@return string? root directory for `file`
function M.get_project_root(file)
  return vim.fs.root(vim.fn.expand(file), M.project_markers)
end

--- Ensure configured data path exists
function M.ensure_data_path_exists()
  if M.data_path_exists then
    return
  end

  local path = Path:new(M.data_path)
  if not path:exists() then
    path:mkdir()
  end
  M.data_path_exists = true
end

--- Get a `Path` object to store pytest fixture data for a project
---@param project_hash string unique hash for project
---@return Path path object to store project data
function M.get_storage_path_for_project(project_hash)
  local full_path = string.format("%s/%s.json", M.data_path, project_hash)
  return Path:new(full_path)
end

--- Store fixture to unique `project_hash` location for project
---@param project_hash string unique hash for project
---@param fixtures_by_test table pytest fixtures for a given file  -- TODO: better typing for this
---@param all_fixtures table all project fixtures
function M.store_fixtures(project_hash, fixtures_by_test, all_fixtures)
  local path = M.get_storage_path_for_project(project_hash)
  local fixtures = {
    fixtures_by_test = fixtures_by_test,
    all_fixtures = all_fixtures,
  }
  local json_encoded_fixtures = vim.json.encode(fixtures)

  vim.uv.fs_open(path:absolute(), "w", 493, function(open_err, fd)
    if open_err ~= nil then
      print("Error opening file: ", open_err)
      return
    end

    vim.uv.fs_write(fd, json_encoded_fixtures, -1, function(write_err, bytes)
      if write_err ~= nil then
        print("Error writing file: ", write_err)
        return
      end

      vim.uv.fs_close(fd, function(close_err)
        if close_err ~= nil then
          print("Error closing file: ", close_err)
        end
      end)
    end)
  end)
end

--- Read project fixtures from cache
---@param file_path Path path to project fixture cache file
---@param fixture_key string fixture key to return (e.g. `fixtures_by_test`, `all_fixtures`)
---@return table fixtures
function M.get_fixtures(file_path, fixture_key)
  local path = Path:new(file_path)
  local raw_fixtures = path:read()

  local fixtures = vim.json.decode(raw_fixtures)
  return fixtures[fixture_key]
end

M.ts_query_text = [[
(function_definition
  name: (identifier) @function
  #match? @function "test_")
  ]]

--- Get the parent test function for the node under cursor
---@return string? function name
function M.get_parent_test_function()
  local node_at_cursor = TSUtils.get_node_at_cursor()

  while node_at_cursor do
    if node_at_cursor:type() == "function_definition" then
      local function_name_node = node_at_cursor:field("name")[1]
      if function_name_node then
        local function_name = vim.treesitter.get_node_text(function_name_node, 0)
        if function_name:match("^test_") then
          return function_name
        end
      end
    end
    node_at_cursor = node_at_cursor:parent()
  end

  return nil
end

--- Convert `target_path` absolute path to a path relative to `base_dir`
---@param base_dir string base directory
---@param target_path string directory
function M.get_relative_path(base_dir, target_path)
  local base_abs = vim.fn.fnamemodify(base_dir, ":p")
  local target_abs = vim.fn.fnamemodify(target_path, ":p")

  if target_abs:sub(1, #base_abs) == base_abs then
    return target_abs:sub(#base_abs + 1)
  else
    return target_abs
  end
end

--- Get details about the test under cursor
---@return string?, string?, string?[] relative file name, function name, function args
function M.get_current_test_info()
  local function_name = M.get_parent_test_function()
  if function_name == nil then
    print("No test function found under cursor")
    return nil, nil, nil
  end
  local test_file = vim.fn.expand("%")
  local project_root = M.get_project_root(test_file)
  if project_root == nil then
    print("Could not find project root; exiting..")
    return
  end
  local relative_file_name = M.get_relative_path(project_root, test_file)

  -- Query the arguments of the function
  local query_string = [[
    (function_definition
      name: (identifier) @name
      parameters: (parameters (identifier) @args))
  ]]

  local lang = "python"
  local parser = vim.treesitter.get_parser(0, lang)
  assert(parser, "parser should not be nil")

  local query = vim.treesitter.query.parse(lang, query_string)
  local root_node = parser:parse()[1]

  local function_args = {}
  for _, match, _ in query:iter_matches(root_node:root(), 0, 0, -1, { all = true }) do
    local name = vim.treesitter.get_node_text(match[1][1], 0)

    if name == function_name then
      local arg = vim.treesitter.get_node_text(match[2][1], 0)
      table.insert(function_args, arg)
    end
  end

  return relative_file_name, function_name, function_args
end

--- Store pytest fixtures in cache dir
---@param project_hash string filename for project fixture cache
---@param output_lines string[] pytest command result to parse
function M.parse_and_store_project_fixtures(project_hash, output_lines)
  local fixtures_by_test = setmetatable({}, {
    __index = function(tbl, key)
      tbl[key] = {}
      return tbl[key]
    end,
  })

  local all_fixtures = {}

  local current_test_name = nil
  local current_test_file_path = nil
  local last_line_was_test_heading = false

  for _, line in ipairs(output_lines) do
    if last_line_was_test_heading then
      current_test_file_path = line:match("%((.-):")
      assert(current_test_name, "current test name is nil")
      fixtures_by_test[current_test_file_path][current_test_name] = {}
      last_line_was_test_heading = false
    else
      local test_match = line:match("fixtures used by ([%w_]+)")
      if test_match then
        current_test_name = test_match
        current_test_file_path = nil
        last_line_was_test_heading = true
      elseif current_test_name then
        local fixture_name, file_path, line_number = line:match("([%w_]+)%s*%-%-%s*([%w%p]+):(%d+)")
        if fixture_name and file_path then
          fixtures_by_test[current_test_file_path][current_test_name][fixture_name] = {
            file_path = file_path,
            line_number = line_number,
          }
          all_fixtures[string.format("%s:%s", file_path, fixture_name)] = {
            file_path = file_path,
            line_number = line_number,
          }
        end
      end
    end
  end

  M.store_fixtures(project_hash, fixtures_by_test, all_fixtures)
end

--- Kick off a `Job` to refresh the pytest fixture cache for this project
---@param project_hash string unique hash for project, used as filename for cache
function M.refresh_pytest_fixture_cache(project_hash)
  local function on_exit(out)
    local output_lines = vim.split(out.stdout, "\n", { trimempty = true })
    M.parse_and_store_project_fixtures(project_hash, output_lines)
  end
  local result = vim.system({ "pytest", "--fixtures-per-test" }, { text = true }, on_exit)
end

--- Determine if the a given filename is of python ft
---@param filename string filename
---@return boolean
function M.is_python(filename)
  local buf = vim.fn.bufadd(vim.fn.expand(filename))
  vim.fn.bufload(buf)
  local filetype = vim.bo[buf].filetype
  return filetype == "python"
end

--- Determine if pytest is an executable on PATH
---@return boolean
function M.has_pytest()
  if vim.fn.executable("pytest") == 1 then
    return true
  else
    if M.debug then
      print("Could not find pytest executable..")
    end
    return false
  end
end

--- Additional predicate check to determine if we should refesh fixture cache
---@param project_hash string unique hash for project
---@return boolean
function M.should_refresh_fixtures(project_hash)
  return true
end

--- Generate a unique hash for the project, based on `project_root`
---@param project_root string fully qualified project root
---@return string unique hash
function M.generate_project_hash(project_root)
  local project_hash = vim.fn.sha256(project_root)
  return project_hash
end

--- Get the current project root and corresponding hash
---@param buf_file string? file to determine project root of
---@return string, string project_root and hash
function M.get_current_project_and_hash(buf_file)
  buf_file = buf_file or vim.fn.expand("%")
  local project_root = M.get_project_root(buf_file)
  assert(project_root, "project root should not be nil")
  local hash = M.generate_project_hash(project_root)
  return project_root, hash
end

--- Parse fixtures for an individual test
---@param test_file_name string file name of test
---@param test_name string of test
---@return table[string] fixture details
function M.parse_fixtures_for_test(test_file_name, test_name)
  local _, project_hash = M.get_current_project_and_hash()
  local project_fixture_file_path = M.get_storage_path_for_project(project_hash)
  local fixtures = M.get_fixtures(project_fixture_file_path, "fixtures_by_test")
  local function_fixtures = fixtures[test_file_name][test_name]
  return function_fixtures
end

--- Open a file at a specified line number
---@param file_path string file path to open
---@param line_number integer line number to jump to
function M.open_file_at_line(file_path, line_number)
  vim.cmd("edit " .. file_path)
  vim.api.nvim_win_set_cursor(0, { line_number, 0 })
end

function M.all_fixtures()
  local _, project_hash = M.get_current_project_and_hash()
  local project_fixture_file_path = M.get_storage_path_for_project(project_hash)
  local fixtures = M.get_fixtures(project_fixture_file_path, "all_fixtures")

  local fixture_names = {}
  for fixture_name, _ in pairs(fixtures) do
    table.insert(fixture_names, fixture_name)
  end

  vim.ui.select(fixture_names, {
    prompt = string.format("Go to fixture: "),
    format_item = function(item)
      return item
    end,
  }, function(fixture)
    if fixture == nil then
      return
    end

    local fixture_info = fixtures[fixture]
    local fixture_line_number = tonumber(fixture_info.line_number) or 0
    -- TODO: should add to tagstack (and make this configurable)
    M.open_file_at_line(fixture_info.file_path, fixture_line_number)
  end)
end

--- Find fixtures associated with test under cursor and prompt to go to them
function M.goto_fixture()
  local test_file_name, test_name, test_args = M.get_current_test_info()
  if test_file_name == nil or test_name == nil then
    return
  end

  local function_fixtures = M.parse_fixtures_for_test(test_file_name, test_name)
  if function_fixtures == nil then
    if M.debug then
      print("No fixtures found!")
    end
    return
  end
  local fixtures = {}
  for fixture, _ in pairs(function_fixtures) do
    table.insert(fixtures, fixture)
  end

  vim.ui.select(fixtures, {
    prompt = string.format("Go to fixture for test %s: ", test_name),
    format_item = function(item)
      return item
    end,
  }, function(fixture)
    if fixture == nil then
      return
    end

    local fixture_info = function_fixtures[fixture]
    local fixture_line_number = tonumber(fixture_info.line_number) or 0
    -- TODO: should add to tagstack (and make this configurable)
    M.open_file_at_line(fixture_info.file_path, fixture_line_number)
  end)
end

function M.maybe_refresh_pytest_fixture_cache(buf_file, opts)
  opts = opts or {}
  local refresh = false
  for match in string.gmatch(buf_file, "./*/test_.*.py") do
    refresh = true
  end
  if not refresh then
    return
  end

  local force = opts.force or false
  local project_root, project_hash = M.get_current_project_and_hash(buf_file)

  if
    M.has_pytest() and force or (project_root and M.is_python(buf_file) and M.should_refresh_fixtures(project_hash))
  then
    if M.debug then
      print("pytest_nvim refreshing cache for " .. vim.fn.expand("%:p"))
    end
    M.refresh_pytest_fixture_cache(project_hash)
  end
end

function M.setup(opts)
  M.project_markers = { ".git", "pyproject.toml", "setup.py", "setup.cfg" }
  M.data_path = string.format("%s/pytest_fixtures", vim.fn.stdpath("data"))
  M.data_path_exists = false
  M.ensure_data_path_exists()

  vim.api.nvim_create_autocmd("FileType", {
    pattern = "python",
    group = vim.api.nvim_create_augroup("pytest_fixtures:user-commands", { clear = true }),
    callback = function()
      vim.api.nvim_create_user_command("PytestFixturesRefresh", function()
        M.maybe_refresh_pytest_fixture_cache(vim.fn.expand("%"), { force = true })
      end, {})
      vim.api.nvim_create_user_command("PytestFixturesProjectCachePath", function()
        local _, project_hash = M.get_current_project_and_hash()
        local cache = M.get_storage_path_for_project(project_hash)
        print("Project cache location: ", cache)
      end, {})
      vim.api.nvim_create_user_command("PytestFixturesTestFixtures", function()
        M.goto_fixture()
      end, {})
      vim.api.nvim_create_user_command("PytestFixturesProjectFixtures", function()
        M.all_fixtures()
      end, {})
    end,
  })

  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "BufWritePost" }, {
    group = vim.api.nvim_create_augroup("pytest_fixtures:refresh", { clear = true }),
    pattern = { "*.py", "*.pyi" },
    callback = function(ev)
      M.maybe_refresh_pytest_fixture_cache(ev.file)
    end,
  })

  vim.keymap.set(
    "n",
    "<localleader>]",
    "<cmd>PytestFixturesTestFixtures<cr>",
    { desc = "PytestFixtures Go To Fixture" }
  )
end

return M
