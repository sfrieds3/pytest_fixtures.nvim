local Path = require("plenary.path")
local TSUtils = require("nvim-treesitter.ts_utils")

local PytestFixturesUtils = {}

PytestFixturesUtils.data_path_exists = false
PytestFixturesUtils.refreshing = false

--- Get project root for a given file based on configured project_markers
---@param file string filename for which to find root directory
---@return string? root directory for `file`
function PytestFixturesUtils.get_project_root(file)
  return vim.fs.root(vim.fn.expand(file), require("pytest_fixtures.config").project_markers)
end

--- Ensure configured data path exists
function PytestFixturesUtils.ensure_data_path_exists()
  if PytestFixturesUtils.data_path_exists then
    return
  end

  local path = Path:new(require("pytest_fixtures.config").data_path)
  if not path:exists() then
    path:mkdir()
  end
  PytestFixturesUtils.data_path_exists = true
end

--- Get a `Path` object to store pytest fixture data for a project
---@param project_hash string unique hash for project
---@return Path path object to store project data
function PytestFixturesUtils.get_storage_path_for_project(project_hash)
  local full_path = string.format("%s/%s.json", require("pytest_fixtures.config").data_path, project_hash)
  return Path:new(full_path)
end

--- Store fixture to unique `project_hash` location for project
---@param project_hash string unique hash for project
---@param fixtures_by_test table pytest fixtures for a given file  -- TODO: better typing for this
---@param all_fixtures table all project fixtures
function PytestFixturesUtils.store_fixtures(project_hash, fixtures_by_test, all_fixtures)
  local path = PytestFixturesUtils.get_storage_path_for_project(project_hash)
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
function PytestFixturesUtils.get_fixtures(file_path, fixture_key)
  local path = Path:new(file_path)
  local raw_fixtures = path:read()

  local fixtures = vim.json.decode(raw_fixtures)
  return fixtures[fixture_key]
end

PytestFixturesUtils.ts_query_text = [[
(function_definition
  name: (identifier) @function
  #match? @function "test_")
  ]]

--- Get the parent test function for the node under cursor
---@return string? function name
function PytestFixturesUtils.get_parent_test_function()
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
function PytestFixturesUtils.get_relative_path(base_dir, target_path)
  local base_abs = vim.fn.fnamemodify(base_dir, ":p")
  local target_abs = vim.fn.fnamemodify(target_path, ":p")

  if target_abs:sub(1, #base_abs) == base_abs then
    return target_abs:sub(#base_abs + 1)
  else
    return target_abs
  end
end

--- Get details about the test under cursor
---@return string?, string?, table? relative file name, function name, function args
function PytestFixturesUtils.get_current_test_info()
  local function_name = PytestFixturesUtils.get_parent_test_function()
  if function_name == nil then
    print("No test function found under cursor")
    return nil, nil, nil
  end
  local test_file = vim.fn.expand("%")
  local project_root = PytestFixturesUtils.get_project_root(test_file)
  if project_root == nil then
    print("Could not find project root; exiting..")
    return
  end
  local relative_file_name = PytestFixturesUtils.get_relative_path(project_root, test_file)

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
function PytestFixturesUtils.parse_and_store_project_fixtures(project_hash, output_lines)
  local fixtures_by_test = setmetatable({}, {
    __index = function(tbl, key)
      tbl[key] = {}
      return tbl[key]
    end,
  })

  local fixtures = setmetatable({}, {
    __index = function(tbl, key)
      tbl[key] = {}
      return tbl[key]
    end,
  })

  function fixtures:add_test(args)
    local t = { file_path = args.file_path, line_number = args.line_number }
    self["test_fixtures"][args.current_test_file_path][args.current_test_name][args.fixture_name] = t
  end

  function fixtures:add_fixture(args)
    local related_test = args["related_test"] or {}
    local fixture_obj = self:get_all_fixtures()[args.fixture] or {}
    local related_tests = fixture_obj["related_tests"] or {}
    if related_test then
      local exists = false
      for _, test in ipairs(related_tests) do
        if test.name == related_test.name and test.path == related_test.path and test.line == related_test.line then
          exists = true
          break
        end
      end
      if not exists then
        table.insert(related_tests, related_test)
      end
    end

    self["all_fixtures"][args.fixture] = {
      file_path = args.file_path,
      line_number = args.line_number,
      related_tests = related_tests,
    }
  end

  function fixtures:get_all_fixtures()
    return self["all_fixtures"]
  end

  local current_test_name = nil
  local current_test_file_path = nil
  local current_test_line_num = nil
  local last_line_was_test_heading = false

  for _, line in ipairs(output_lines) do
    if last_line_was_test_heading then
      current_test_file_path, current_test_line_num = line:match("%((.-):(.+)%)")
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

          fixtures:add_fixture({
            fixture = string.format("%s:%s", file_path, fixture_name),
            file_path = file_path,
            line_number = line_number,
            related_test = {
              name = current_test_name,
              path = current_test_file_path,
              line = current_test_line_num,
            },
          })
        end
      end
    end
  end

  PytestFixturesUtils.store_fixtures(project_hash, fixtures_by_test, fixtures:get_all_fixtures())
end

--- Kick off a `Job` to refresh the pytest fixture cache for this project
---@param project_hash string unique hash for project, used as filename for cache
function PytestFixturesUtils.refresh_pytest_fixture_cache(project_hash)
  local function on_exit(out)
    local output_lines = vim.split(out.stdout, "\n", { trimempty = true })
    PytestFixturesUtils.parse_and_store_project_fixtures(project_hash, output_lines)
  end
  local result = vim.system({ "pytest", "--fixtures-per-test" }, { text = true }, on_exit)
end

--- Determine if the a given filename is of python ft
---@param filename string filename
---@return boolean
function PytestFixturesUtils.is_python(filename)
  local buf = vim.fn.bufadd(vim.fn.expand(filename))
  vim.fn.bufload(buf)
  local filetype = vim.bo[buf].filetype
  return filetype == "python"
end

--- Determine if pytest is an executable on PATH
---@return boolean
function PytestFixturesUtils.has_pytest()
  if vim.fn.executable("pytest") == 1 then
    return true
  else
    if PytestFixturesUtils.debug then
      print("Could not find pytest executable..")
    end
    return false
  end
end

--- Additional predicate check to determine if we should refesh fixture cache
---@param project_hash string unique hash for project
---@return boolean
function PytestFixturesUtils.should_refresh_fixtures(project_hash)
  return true
end

--- Generate a unique hash for the project, based on `project_root`
---@param project_root string fully qualified project root
---@return string unique hash
function PytestFixturesUtils.generate_project_hash(project_root)
  local project_hash = vim.fn.sha256(project_root)
  return project_hash
end

--- Get the current project root and corresponding hash
---@param buf_file string? file to determine project root of
---@return string, string project_root and hash
function PytestFixturesUtils.get_current_project_and_hash(buf_file)
  buf_file = buf_file or vim.fn.expand("%")
  local project_root = PytestFixturesUtils.get_project_root(buf_file)
  assert(project_root, "project root should not be nil")
  local hash = PytestFixturesUtils.generate_project_hash(project_root)
  return project_root, hash
end

--- Parse fixtures for an individual test
---@param test_file_name string file name of test
---@param test_name string of test
---@return table[string] fixture details
function PytestFixturesUtils.parse_fixtures_for_test(test_file_name, test_name)
  local _, project_hash = PytestFixturesUtils.get_current_project_and_hash()
  local project_fixture_file_path = PytestFixturesUtils.get_storage_path_for_project(project_hash)
  local fixtures = PytestFixturesUtils.get_fixtures(project_fixture_file_path, "fixtures_by_test")
  local function_fixtures = fixtures[test_file_name][test_name]
  return function_fixtures
end

--- Open a file at a specified line number
---@param file_path string file path to open
---@param line_number integer line number to jump to
function PytestFixturesUtils.open_file_at_line(file_path, line_number)
  vim.cmd.edit({ args = { file_path }, bang = true })
  vim.api.nvim_win_set_cursor(0, { line_number, 0 })
end

function PytestFixturesUtils.maybe_refresh_pytest_fixture_cache(buf_file, opts)
  if PytestFixturesUtils.refreshing then
    return
  end
  PytestFixturesUtils.refreshing = true

  opts = opts or {}
  PytestFixturesUtils.ensure_data_path_exists()
  local refresh = false
  for _ in string.gmatch(buf_file, "./*/test_.*.py") do
    refresh = true
  end
  if not refresh then
    return
  end

  local force = opts.force or false
  local project_root, project_hash = PytestFixturesUtils.get_current_project_and_hash(buf_file)

  if
    PytestFixturesUtils.has_pytest()
    and (
      force
      or (
        project_root
        and PytestFixturesUtils.is_python(buf_file)
        and PytestFixturesUtils.should_refresh_fixtures(project_hash)
      )
    )
  then
    if PytestFixturesUtils.debug then
      print("pytest_nvim refreshing cache for " .. vim.fn.expand("%:p"))
    end
    PytestFixturesUtils.refresh_pytest_fixture_cache(project_hash)
  end
  PytestFixturesUtils.refreshing = false
end

function PytestFixturesUtils.ui_select(opts)
  local items = opts.items
  local prompt = opts.prompt
  local callback = opts.callback
  local context = opts.context or nil
  local format_func = opts.format_func or function(item)
    return item
  end

  vim.ui.select(items, {
    prompt = prompt,
    format_item = function(item)
      return format_func(item)
    end,
  }, function(item)
    callback(item, context)
  end)
end

return PytestFixturesUtils
