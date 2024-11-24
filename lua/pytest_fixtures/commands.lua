local Api = require("pytest_fixtures.api")
local Utils = require("pytest_fixtures.utils")
local PytestFixturesCommands = {}

function PytestFixturesCommands.setup(opts)
  vim.api.nvim_create_autocmd(opts.refresh_events, {
    group = vim.api.nvim_create_augroup("pytest_fixtures:refresh", { clear = true }),
    pattern = { "*.py", "*.pyi" },
    callback = function(ev)
      Utils.maybe_refresh_pytest_fixture_cache(ev.file)
    end,
  })

  vim.api.nvim_create_autocmd("FileType", {
    pattern = "python",
    group = vim.api.nvim_create_augroup("pytest_fixtures:user-commands", { clear = true }),
    callback = function()
      vim.api.nvim_create_user_command("PytestFixturesRefresh", function()
        Utils.maybe_refresh_pytest_fixture_cache(vim.fn.expand("%"), { force = true })
      end, {})

      vim.api.nvim_create_user_command("PytestFixturesProjectCachePath", function()
        local _, project_hash = Utils.get_current_project_and_hash()
        local cache = Utils.get_storage_path_for_project(project_hash)
        print("Project cache location: ", cache)
      end, {})

      vim.api.nvim_create_user_command("PytestFixturesTestFixtures", function()
        Api.goto_fixture()
      end, {})

      vim.api.nvim_create_user_command("PytestFixturesProjectFixtures", function()
        Api.all_fixtures()
      end, {})

      vim.api.nvim_create_user_command("PytestFixturesReverseLookup", function()
        Api.reverse_lookup()
      end, {})
    end,
  })
end

return PytestFixturesCommands
