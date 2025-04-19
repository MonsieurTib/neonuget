local syntax = require("neonuget.syntax")

local M = {}

function M.setup()
	vim.api.nvim_create_augroup("neonuget_filetype", { clear = true })

	vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
		group = "neonuget_filetype",
		pattern = { "NuGet_*" },
		callback = function()
			vim.bo.filetype = "neonuget"
		end,
	})

	vim.api.nvim_create_autocmd("FileType", {
		group = "neonuget_filetype",
		pattern = "neonuget",
		callback = function()
			syntax.setup()
		end,
	})
end

return M
