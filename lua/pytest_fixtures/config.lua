local utils = require("pytest_fixtures.utils")
local PytestFixturesConfig = {}
local config = {}

local defaults = {
  debug = false,
  keymaps = {
    ["<localleader>]"] = "PytestFixturesTestFixtures",
    ["<localleader>}"] = "PytestFixturesProjectFixtures",
  },
  create_user_commands = true,
  refresh_events = { "BufEnter", "BufWinEnter", "BufWritePost" },
  project_markers = { ".git", "pyproject.toml", "setup.py", "setup.cfg" },
  data_path = string.format("%s/pytest_fixtures", vim.fn.stdpath("data")),
}

function PytestFixturesConfig.setup(opts)
  opts = opts or {}
  config = vim.tbl_extend("force", defaults, opts)

  if config.create_user_commands then
    require("pytest_fixtures.commands").setup(config)
  end

  require("pytest_fixtures.keymaps").setup(config)
end

return setmetatable(PytestFixturesConfig, {
  __index = function(_, key)
    config = config or PytestFixturesConfig.setup()
    return config[key]
  end,
})
