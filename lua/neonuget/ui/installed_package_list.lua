local M = {}

local utils = require("neonuget.ui.utils")
local baseui = require("neonuget.ui.baseui")

function M.create(opts)
	opts = opts or {}
	local packages = opts.packages or {}
	local width = opts.width or 30
	local height = opts.height or 20
	local col = opts.col or 0
	local row = opts.row or 0
	local on_select = opts.on_select or function() end

	local list_highlight_namespace_id = vim.api.nvim_create_namespace("neonuget_installed_list_highlights")

	local function sort_packages(pkgs)
		table.sort(pkgs, function(a, b)
			return a.name < b.name
		end)
		return pkgs
	end

	local top_level_packages = {}

	for _, pkg in ipairs(packages) do
		if pkg.is_top_level or pkg.section == "Top-level" then
			table.insert(top_level_packages, pkg)
		end
	end

	top_level_packages = sort_packages(top_level_packages)
	local original_packages = vim.deepcopy(top_level_packages)

	local package_lookup = {}
	local package_indices = {}
	local last_selected_pkg_name = nil

	local function filter_packages(term)
		if not term or term == "" then
			return original_packages
		end

		local filtered = {}
		term = term:lower()

		for _, pkg in ipairs(original_packages) do
			if pkg.name:lower():find(term, 1, true) then
				table.insert(filtered, pkg)
			end
		end

		return filtered
	end

	local function update_list_display(search_term, target_component)
		local comp = target_component or component

		if not comp then
			return {}, {}
		end

		local filtered_packages = filter_packages(search_term or "")
		local list_content = {}
		local line_highlights = {} -- To store highlight info
		local new_package_lookup = {}
		local new_package_indices = {}

		-- If we have no packages yet, show loading state
		if #original_packages == 0 then
			list_content = { "Loading installed packages..." }
		else
			for i, pkg in ipairs(filtered_packages) do
				local base_line = pkg.name .. " (" .. pkg.resolved_version .. ")"
				local full_line = base_line

				if pkg.latest_version and pkg.latest_version ~= "" and pkg.latest_version ~= pkg.resolved_version then
					local update_suffix = " -> " .. pkg.latest_version
					full_line = base_line .. update_suffix

					table.insert(line_highlights, {
						line = #list_content, -- 0-indexed line for nvim_buf_add_highlight
						start_col = string.len(base_line), -- 0-indexed start col of the suffix
						end_col = string.len(full_line),   -- 0-indexed end col (exclusive) of the suffix
						group = "NuGetUpdateAvailable",
					})
				end

				table.insert(list_content, full_line)
				new_package_lookup[i] = pkg
				new_package_indices[#list_content] = i
			end

			if #filtered_packages == 0 then
				list_content = { "No packages found matching: " .. (search_term or "") }
			end
		end

		if comp.buf and vim.api.nvim_buf_is_valid(comp.buf) then
			comp.set_lines(list_content)

			-- Apply highlights
			vim.api.nvim_buf_clear_namespace(comp.buf, list_highlight_namespace_id, 0, -1)
			for _, hl in ipairs(line_highlights) do
				vim.api.nvim_buf_add_highlight(comp.buf, list_highlight_namespace_id, hl.group, hl.line, hl.start_col, hl.end_col)
			end
		end

		return new_package_lookup, new_package_indices
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
			local selected_pkg = package_lookup[package_indices[line_num]]
			last_selected_pkg_name = selected_pkg.name
			on_select(selected_pkg)
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
		title = "Installed Packages",
		width = width,
		height = height,
		col = col,
		row = row,
		buffer_name = "NuGet_Package_List",
		initial_content = { "Loading packages..." },
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
			["/"] = handle_search,
			["<Tab>"] = handle_tab,
			["q"] = handle_close,
			["<Esc>"] = handle_close,
			["u"] = function()
				local selected_pkg = component.get_selected_package()
				if not selected_pkg then
					vim.notify("No package selected", vim.log.levels.WARN)
					return
				end

				vim.ui.select({ "Yes", "No" }, { prompt = "Uninstall " .. selected_pkg.name .. "?" }, function(choice)
					if choice == "Yes" then
						component.set_loading("Uninstalling " .. selected_pkg.name .. "...")

						require("neonuget").uninstall_package(selected_pkg.name, function(success, packages)
							component.clear_loading()

							if success then
								component._select_first_after_update = true
								if packages then
									component.update_packages(packages)
								else
									require("neonuget").refresh_packages(function(refreshed_packages)
										component.update_packages(refreshed_packages)
									end)
								end
							end
						end)
					end
				end)
			end,
		},
	})

	utils.setup_section_navigation(component.buf)

	package_lookup, package_indices = update_list_display("", component)

	if #top_level_packages > 0 and package_lookup[1] then
		if package_indices[1] and component.win and vim.api.nvim_win_is_valid(component.win) then
			for line_num, idx in pairs(package_indices) do
				if idx == 1 then
					if line_num > 0 and line_num <= vim.api.nvim_buf_line_count(component.buf) then
						vim.api.nvim_win_set_cursor(component.win, { line_num, 0 })
						break
					end
				end
			end
		end
	end

	component.update = function(search_term)
		package_lookup, package_indices = update_list_display(search_term, component)
	end

	component.update_packages = function(new_packages)
		local top_level_packages = {}

		for _, pkg in ipairs(new_packages) do
			if pkg.is_top_level or pkg.section == "Top-level" then
				table.insert(top_level_packages, pkg)
			end
		end

		top_level_packages = sort_packages(top_level_packages)
		original_packages = vim.deepcopy(top_level_packages)

		package_lookup, package_indices = update_list_display("", component)

		if component.win and vim.api.nvim_win_is_valid(component.win) then
			utils.configure_window(component.win, {
				number = false,
				relativenumber = false,
				signcolumn = "no",
				foldcolumn = "0",
				scrolloff = 5,
				sidescrolloff = 5,
				wrap = opts.wrap or false,
				cursorline = opts.cursorline or true,
			})
		end

		if component._select_first_after_update and #top_level_packages > 0 and package_lookup[1] then
			component._select_first_after_update = nil

			for line_num, pkg_idx in pairs(package_indices) do
				if pkg_idx == 1 then
					if
						component.win
						and vim.api.nvim_win_is_valid(component.win)
						and line_num > 0
						and line_num <= vim.api.nvim_buf_line_count(component.buf)
					then
						vim.api.nvim_win_set_cursor(component.win, { line_num, 0 })
						on_select(package_lookup[1])
						last_selected_pkg_name = package_lookup[1].name
						break
					end
				end
			end
		elseif component._select_after_update or last_selected_pkg_name then
			local package_to_select = component._select_after_update or last_selected_pkg_name
			component._select_after_update = nil

			if package_to_select then
				local found = false

				for idx, pkg in pairs(package_lookup) do
					if pkg.name == package_to_select then
						for line_num, pkg_idx in pairs(package_indices) do
							if pkg_idx == idx then
								if
									component.win
									and vim.api.nvim_win_is_valid(component.win)
									and line_num > 0
									and line_num <= vim.api.nvim_buf_line_count(component.buf)
								then
									vim.api.nvim_win_set_cursor(component.win, { line_num, 0 })
									on_select(pkg) -- Select the package to update version list
									found = true
									break
								end
							end
						end
						if found then
							break
						end
					end
				end
			end
		end
	end

	component.set_loading = function(message)
		if component.buf and vim.api.nvim_buf_is_valid(component.buf) then
			component._saved_content = vim.api.nvim_buf_get_lines(component.buf, 0, -1, false)
			vim.api.nvim_buf_set_option(component.buf, "modifiable", true)
			vim.api.nvim_buf_set_lines(component.buf, 0, -1, false, { message or "Loading..." })
			vim.api.nvim_buf_set_option(component.buf, "modifiable", false)
		end
	end

	component.clear_loading = function()
		if component.buf and vim.api.nvim_buf_is_valid(component.buf) and component._saved_content then
			vim.api.nvim_buf_set_option(component.buf, "modifiable", true)
			vim.api.nvim_buf_set_lines(component.buf, 0, -1, false, component._saved_content)
			vim.api.nvim_buf_set_option(component.buf, "modifiable", false)
			component._saved_content = nil

			if component.win and vim.api.nvim_win_is_valid(component.win) then
				utils.configure_window(component.win, {
					number = false,
					relativenumber = false,
					signcolumn = "no",
					foldcolumn = "0",
					scrolloff = 5,
					sidescrolloff = 5,
					wrap = opts.wrap or false,
					cursorline = opts.cursorline or true,
				})
			end
		end
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
