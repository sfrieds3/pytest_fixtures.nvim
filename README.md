# pytest_fixtures.nvim

Easily jump to pytest fixtures.

## Installation

lazy.nvim:

```lua
  {
    "sfrieds3/pytest_fixtures.nvim",
    opts = {
      -- configuration goes here
    },
  },
```

## Usage

When in a python file, simply run `:PytestFixturesRefresh` to refresh the current projects pytest fixtures cache. Then, when your cursor is on a test, hit `<localleader>]` to bring up a floating window with a list of fixtures used by the current test. Selecting any one will bring you to the soruce for that test. Simple as that.

Currently, there is minimal to no configuration options available. But that will change soon.

## Planned Features

- [x] More configuration options
- [x] Better autocmd configuration to keep the cache updated real-time
- [x] Go-to any fixture in the project, not just those under cursor
- [x] Reverse search; i.e. see which tests use the fixture under cursor
