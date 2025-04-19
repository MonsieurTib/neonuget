local M = {}

local utils = require("neonuget.ui.utils")
local nuget = require("neonuget.nuget")
local baseui = require("neonuget.ui.baseui")

function M.create(opts)
	opts = opts or {}
	local width = opts.width or 30
	local height = opts.height or 20
	local col = opts.col or 0
	local row = opts.row or 0
	local on_select = opts.on_select or function() end
	local params = opts.params or {}

	local available_packages = {}
	local package_lookup = {}
	local package_indices = {}

	local update_list_display

	local function fetch_packages(comp)
		if not comp or not comp.buf or not vim.api.nvim_buf_is_valid(comp.buf) then
			vim.notify("fetch_packages: Invalid component", vim.log.levels.ERROR)
			return
		end

		vim.api.nvim_buf_set_option(comp.buf, "modifiable", true)
		vim.api.nvim_buf_set_lines(comp.buf, 0, -1, false, { "Loading available packages..." })
		vim.api.nvim_buf_set_option(comp.buf, "modifiable", false)

		nuget.fetch_available_packages(params, function(result)
			if not comp or not comp.buf or not vim.api.nvim_buf_is_valid(comp.buf) then
				vim.notify("fetch_packages callback: Component is no longer valid", vim.log.levels.ERROR)
				return
			end

			if not result or not result.packages then
				vim.api.nvim_buf_set_option(comp.buf, "modifiable", true)
				vim.api.nvim_buf_set_lines(comp.buf, 0, -1, false, { "No packages found" })
				vim.api.nvim_buf_set_option(comp.buf, "modifiable", false)
				return
			end

			update_list_display(comp, result.packages)
		end)
	end

	update_list_display = function(comp, pkgs)
		if not comp or not comp.buf or not vim.api.nvim_buf_is_valid(comp.buf) then
			vim.notify("update_list_display: Invalid component or buffer", vim.log.levels.ERROR)
			return
		end

		available_packages = pkgs or {}

		local list_content = {}
		package_lookup = {}
		package_indices = {}

		for i, pkg in ipairs(available_packages) do
			local line = pkg.name .. " (" .. pkg.latest_version .. ")"

			table.insert(list_content, line)
			package_lookup[i] = pkg
			package_indices[#list_content] = i
		end

		if #available_packages == 0 then
			list_content = { "No packages found" }
		end

		vim.api.nvim_buf_set_option(comp.buf, "modifiable", true)
		vim.api.nvim_buf_set_lines(comp.buf, 0, -1, false, list_content)
		vim.api.nvim_buf_set_option(comp.buf, "modifiable", false)
	end

	local function handle_enter(buf, win)
		if not win or not vim.api.nvim_win_is_valid(win) then
			return
		end

		local cursor = vim.api.nvim_win_get_cursor(win)
		local line_num = cursor[1]

		if line_num <= 0 or line_num > vim.api.nvim_buf_line_count(buf) then
			return
		end

		if
			package_indices
			and package_indices[line_num]
			and package_lookup
			and package_lookup[package_indices[line_num]]
		then
			on_select(package_lookup[package_indices[line_num]])
		end
	end

	local function handle_search()
		if opts.on_search then
			opts.on_search()
		end
	end

	local function handle_tab()
		if opts.on_tab then
			opts.on_tab()
		end
	end

	local function handle_close()
		if opts.on_close then
			opts.on_close()
		end
	end

	local component = baseui.create_component({
		title = "Available Packages",
		width = width,
		height = height,
		col = col,
		row = row,
		buffer_name = "NuGet_Available_Package_List",
		initial_content = { "Loading available packages..." },
		cursorline = true,
		mappings = {},
	})

	if not component then
		return nil
	end

	utils.set_buffer_mappings(component.buf, {
		n = {
			["<CR>"] = function()
				handle_enter(component.buf, component.win)
			end,
			["r"] = function()
				fetch_packages(component)
			end,
			["/"] = handle_search,
			["<Tab>"] = handle_tab,
			["q"] = handle_close,
			["<Esc>"] = handle_close,
		},
	})

	fetch_packages(component)

	component.update_params = function(new_params)
		for k, v in pairs(new_params) do
			params[k] = v
		end

		fetch_packages(component)
	end

	component.get_selected_package = function()
		if not component.win or not vim.api.nvim_win_is_valid(component.win) then
			return nil
		end

		local cursor = vim.api.nvim_win_get_cursor(component.win)
		local line_num = cursor[1]

		if line_num <= 0 or line_num > vim.api.nvim_buf_line_count(component.buf) then
			return nil
		end

		if
			package_indices
			and package_indices[line_num]
			and package_lookup
			and package_lookup[package_indices[line_num]]
		then
			return package_lookup[package_indices[line_num]]
		end

		return nil
	end

	return component
end

return M
