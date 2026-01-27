local M = {}

local utils = require("neonuget.ui.utils")
local baseui = require("neonuget.ui.baseui")

function M.create(opts)
	opts = opts or {}
	local pkg = opts.package
	local width = opts.width or 40
	local height = opts.height or 10
	local col = opts.col or 0
	local row = opts.row or 0
	local on_select = opts.on_select or function() end

	local active_components = _G.active_components

	if not pkg then
		vim.notify("No package provided for version list", vim.log.levels.ERROR)
		return nil
	end

	local version_data = {}
	local current_line = 0
	local update_versions

	local component = baseui.create_component({
		title = "Versions: " .. pkg.name,
		width = width,
		height = height,
		col = col,
		row = row,
		buffer_name = "NuGet_Package_Versions_" .. pkg.name,
		initial_content = { "Loading versions..." },
		wrap = true,
		cursorline = true,
		filetype = "markdown",
		focus = true,
		mappings = {},
	})

	if not component then
		return nil
	end

	local nuget = require("neonuget.nuget")

	update_versions = function(versions_array)
		if not component.buf or not vim.api.nvim_buf_is_valid(component.buf) then
			return
		end

		if not versions_array or #versions_array == 0 then
			vim.api.nvim_buf_set_option(component.buf, "modifiable", true)
			vim.api.nvim_buf_set_lines(component.buf, 0, -1, false, { "No versions found for " .. pkg.name })
			vim.api.nvim_buf_set_option(component.buf, "modifiable", false)
			return
		end

		local content = {}

		version_data = {}
		current_line = 1

		local standardized_versions = {}
		for i, v in ipairs(versions_array) do
			local version_text
			local version_obj = {}

			if type(v) == "string" then
				-- Simple string version
				version_text = v
				version_obj = { version = v }
			elseif type(v) == "table" then
				if v.text then
					version_text = v.text
					version_obj = v.data or v
				elseif v.version then
					version_text = v.version
					version_obj = v
				else
					vim.notify("Unknown version format: " .. vim.inspect(v), vim.log.levels.DEBUG)
					goto continue
				end
			else
				vim.notify("Unknown version type: " .. type(v), vim.log.levels.DEBUG)
				goto continue
			end

			if not version_text or version_text == "" then
				goto continue
			end

			table.insert(standardized_versions, {
				text = version_text,
				data = version_obj,
			})

			local version_split = {}
			local count = 1
			for str in string.gmatch(version_text, "[^%.]+") do
				version_split[count] = tonumber(str)
				count = count + 1
			end

			table.insert(standardized_versions, {
				text = version_text,
				data = version_obj,
				version_split = version_split,
			})

			::continue::
		end

		table.sort(standardized_versions, function(a, b)
			for index, value in ipairs(a.version_split) do
				if b.version_split[index] == nil then
					return true
				end
				if value ~= b.version_split[index] then
					return value > b.version_split[index]
				end
			end
			return false
		end)

		for i, v in ipairs(standardized_versions) do
			local version = v.text
			local version_info = v.data
			local line_num = #content + 1

			local display_text = version

			if version == pkg.resolved_version then
				display_text = display_text .. " (current)"
				current_line = line_num
			end

			if i == 1 then
				display_text = display_text .. " (latest)"
			end

			table.insert(content, display_text)
			version_data[line_num] = version

			if not component.version_info_map then
				component.version_info_map = {}
			end
			component.version_info_map[version] = version_info
		end

		vim.api.nvim_buf_set_option(component.buf, "modifiable", true)
		vim.api.nvim_buf_set_lines(component.buf, 0, -1, false, content)
		vim.api.nvim_buf_set_option(component.buf, "modifiable", false)

		if component.win and vim.api.nvim_win_is_valid(component.win) and current_line > 0 then
			vim.api.nvim_win_set_cursor(component.win, { current_line, 0 })
		end
	end

	local augroup_name = "NuGetVersionSelect_" .. pkg.name
	local augroup = vim.api.nvim_create_augroup(augroup_name, { clear = true })
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = augroup,
		buffer = component.buf,
		callback = function()
			if component.win and vim.api.nvim_win_is_valid(component.win) then
				local cursor = vim.api.nvim_win_get_cursor(component.win)
				local line = cursor[1]
				local version = version_data[line]

				if version then
					on_select(version)
				end
			end
		end,
	})

	local original_close = component.close
	component.close = function()
		pcall(vim.api.nvim_del_augroup_by_name, augroup_name)
		original_close()
	end

	component.update = update_versions

	component.get_selected_version = function()
		if not component.win or not vim.api.nvim_win_is_valid(component.win) then
			return nil
		end

		local cursor = vim.api.nvim_win_get_cursor(component.win)
		local line = cursor[1]

		return version_data[line]
	end

	component.setup_key_handlers = function()
		vim.api.nvim_buf_set_keymap(component.buf, "n", "<CR>", "", {
			callback = function()
				if opts.on_enter then
					opts.on_enter()
				end
			end,
			noremap = true,
			silent = true,
		})

		vim.api.nvim_buf_set_keymap(component.buf, "n", "i", "", {
			callback = function()
				local selected_version = component.get_selected_version()
				local pkg_name = pkg.name

				if selected_version and pkg_name then
					if active_components and active_components.package_list then
						active_components.package_list.set_loading(
							"Installing " .. pkg_name .. " " .. selected_version .. "..."
						)
					end

					require("neonuget").install_package(pkg_name, selected_version, function(success)
						if active_components and active_components.package_list then
							active_components.package_list.clear_loading()

							if success then
								require("neonuget").refresh_packages(function(packages)
									if active_components and active_components.package_list then
										active_components.package_list._select_after_update = pkg_name
										active_components.package_list.update_packages(packages)
									end

									if active_components then
										for _, comp in pairs(active_components) do
											if comp and comp.win and vim.api.nvim_win_is_valid(comp.win) then
												utils.configure_window(comp.win, {
													number = false,
													relativenumber = false,
												})
											end
										end
									end

									if pkg_name == pkg.name then
										nuget.fetch_all_package_versions(pkg.name, function(versions_array)
											if active_components and active_components.version_list then
												active_components.version_list.update(versions_array)
											end
										end)
									end
								end)
							end
						end
					end)
				end
			end,
			noremap = true,
			silent = true,
		})

		vim.api.nvim_buf_set_keymap(component.buf, "n", "<Tab>", "", {
			callback = function()
				if opts.on_tab then
					opts.on_tab()
				end
			end,
			noremap = true,
			silent = true,
		})

		vim.api.nvim_buf_set_keymap(component.buf, "n", "q", "", {
			callback = function()
				if opts.on_close then
					opts.on_close()
				end
			end,
			noremap = true,
			silent = true,
		})

		vim.api.nvim_buf_set_keymap(component.buf, "n", "<Esc>", "", {
			callback = function()
				if opts.on_close then
					opts.on_close()
				end
			end,
			noremap = true,
			silent = true,
		})
	end

	component.setup_key_handlers()

	utils.setup_section_navigation(component.buf)

	return component
end

return M
