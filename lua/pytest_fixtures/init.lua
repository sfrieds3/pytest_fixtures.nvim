FORCE_RELOAD = true
if FORCE_RELOAD then
  package.loaded["pytest_fixtures"] = nil
end

local PytestFixtures = {}

function PytestFixtures.setup(opts)
  require("pytest_fixtures.config").setup(opts)
end

return setmetatable(PytestFixtures, {
  __index = function(_, key)
    return require("pytest_fixtures.api")[key]
  end,
})
