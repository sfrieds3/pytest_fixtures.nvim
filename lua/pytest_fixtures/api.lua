local Utils = require("pytest_fixtures.utils")
local PytestFxituresApi = {}

function PytestFxituresApi.all_fixtures()
  local _, project_hash = Utils.get_current_project_and_hash()
  local project_fixture_file_path = Utils.get_storage_path_for_project(project_hash)
  local fixtures = Utils.get_fixtures(project_fixture_file_path, "all_fixtures")

  local fixture_names = {}
  for fixture_name, _ in pairs(fixtures) do
    table.insert(fixture_names, fixture_name)
  end

  Utils.ui_select({
    items = fixture_names,
    prompt = string.format("Go to fixture: "),
    callback = function(fixture)
      if fixture == nil then
        return
      end

      local fixture_info = fixtures[fixture]
      local fixture_line_number = tonumber(fixture_info.line_number) or 0
      -- TODO: should add to tagstack (and make this configurable)
      Utils.open_file_at_line(fixture_info.file_path, fixture_line_number)
    end,
  })
end

--- Find fixtures associated with test under cursor and prompt to go to them
function PytestFxituresApi.goto_fixture()
  local test_file_name, test_name, test_args = Utils.get_current_test_info()
  if test_file_name == nil or test_name == nil then
    return
  end

  local function_fixtures = Utils.parse_fixtures_for_test(test_file_name, test_name)
  if function_fixtures == nil then
    if require("pytest_fixtures.config").debug then
      print("No fixtures found!")
    end
    return
  end
  local fixtures = {}
  for fixture, _ in pairs(function_fixtures) do
    table.insert(fixtures, fixture)
  end

  Utils.ui_select({
    items = fixtures,
    prompt = string.format("Go to fixture for test %s: ", test_name),
    callback = function(fixture)
      if fixture == nil then
        return
      end

      local fixture_info = function_fixtures[fixture]
      local fixture_line_number = tonumber(fixture_info.line_number) or 0
      -- TODO: should add to tagstack (and make this configurable)
      Utils.open_file_at_line(fixture_info.file_path, fixture_line_number)
    end,
  })
end

--- Reverse lookup a fixture to see which tests use it
---@param opts table
function PytestFxituresApi.reverse_lookup(opts)
  -- local current_fixture = opts["current"] or false
  local _, project_hash = Utils.get_current_project_and_hash()
  local project_fixture_file_path = Utils.get_storage_path_for_project(project_hash)
  local fixtures = Utils.get_fixtures(project_fixture_file_path, "all_fixtures")
  local fixture_names = {}
  for fixture, _ in pairs(fixtures) do
    table.insert(fixture_names, fixture)
  end

  Utils.ui_select({
    items = fixture_names,
    prompt = "Select a fixture: ",
    context = fixtures,
    format_func = function(item)
      return item
    end,
    callback = function(fixture, context)
      if fixture == nil then
        return
      end
      local related_tests = context[fixture]["related_tests"]
      if related_tests == nil then
        print("No related tests found for this fixture")
        return
      end

      Utils.ui_select({
        items = related_tests,
        prompt = string.format("Tests using fixture %s: ", fixture),
        format_func = function(item)
          return string.format("%s:%s", item.path, item.name)
        end,
        callback = function(test)
          if test == nil or test.path == nil or test.line == nil then
            print("Invalid test selection...")
            return
          end

          local test_line_number = tonumber(test.line) or 0
          Utils.open_file_at_line(test.path, test_line_number)
        end,
      })
    end,
  })
end

return PytestFxituresApi
