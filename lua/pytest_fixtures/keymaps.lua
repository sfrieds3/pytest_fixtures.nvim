local PytestFixturesKeymaps = {}

function PytestFixturesKeymaps.setup(opts)
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "python",
    group = vim.api.nvim_create_augroup("pytest_fixtures:keymaps", { clear = true }),
    callback = function()
      for key, method in pairs(opts.keymaps) do
        vim.keymap.set("n", key, string.format("<cmd>%s<cr>", method), { buffer = true, desc = method })
      end
    end,
  })
end

return PytestFixturesKeymaps
