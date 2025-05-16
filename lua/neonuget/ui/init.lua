local M = {}

local utils = require("neonuget.ui.utils")
local search_component = require("neonuget.ui.search")
local package_list_component = require("neonuget.ui.installed_package_list")
local version_list_component = require("neonuget.ui.version_list")
local details_component = require("neonuget.ui.details")
local available_package_list_component = require("neonuget.ui.available_package_list")
local nuget = require("neonuget.nuget")

utils.setup_highlights()

function M.display_dual_pane(packages, opts)
	opts = opts or {}

	local background = utils.create_background()

	local dimensions = utils.calculate_centered_dimensions(0.8, 0.8)
	local total_width = dimensions.width
	local total_height = dimensions.height
	local col = dimensions.col
	local row = dimensions.row

	local margin = 2

	local list_width = math.floor(total_width * 0.4)
	local details_width = total_width - list_width - 1 - margin
	local search_height = 1

	local versions_height = math.floor(total_height * 0.3)
	local details_height = total_height - versions_height - 1 - margin
	local right_pane_height = versions_height + details_height + 1 + margin

	local left_pane_height = right_pane_height
	local left_content_height = left_pane_height - search_height - margin * 2 - 2
	local installed_height = math.floor(left_content_height * 0.5)
	local available_height = left_content_height - installed_height

	local search_col, search_row = col, row
	local installed_col, installed_row = col, row + search_height + 1 + margin
	local available_col, available_row = col, row + search_height + 1 + margin + installed_height + margin + 1
	local versions_col, versions_row = col + list_width + 1 + margin, row

	local function get_search_pos()
		return search_col, search_row
	end

	local function get_installed_pos()
		return installed_col, installed_row
	end

	local function get_available_pos()
		return available_col, available_row
	end

	local active_components = {
		background = background,
	}

	_G.active_components = active_components

	local function reset_border_colors(focused_component)
		for component_name, component in pairs(active_components) do
			if
				component_name ~= "background"
				and component_name ~= focused_component
				and component
				and component.win
			then
				utils.set_focused_border_color(component.win, false)
			end
		end
	end

	local function close_all_components()
		for _, component in pairs(active_components) do
			if component and component.close then
				component.close()
			end
		end

		utils.close_windows_by_pattern({
			"NuGet_Package_Versions_",
			"NuGet_Package_Details_",
		})
	end

	local function expand_to_full_width()
		if active_components.search then
			local search_col, search_row = get_search_pos()
			active_components.search.resize(list_width, search_height, search_col, search_row)
		end

		if active_components.package_list then
			local installed_col, installed_row = get_installed_pos()
			active_components.package_list.resize(total_width, installed_height, installed_col, installed_row)
		end

		if active_components.available_package_list then
			local available_col, available_row = get_available_pos()
			active_components.available_package_list.resize(total_width, available_height, available_col, available_row)
		end
	end

	local function handle_package_selection(pkg)
		if active_components.version_list then
			active_components.version_list.close()
			active_components.version_list = nil
		end
		if active_components.details then
			active_components.details.close()
			active_components.details = nil
		end

		if active_components.package_list then
			active_components.package_list.resize(list_width, installed_height, installed_col, installed_row)
		end
		if active_components.available_package_list then
			active_components.available_package_list.resize(list_width, available_height, available_col, available_row)
		end
		if active_components.search then
			active_components.search.resize(list_width, search_height, search_col, search_row)
		end

		local version_list = version_list_component.create({
			package = pkg,
			width = details_width,
			height = versions_height,
			col = versions_col,
			row = versions_row,
			on_select = function(version)
				if active_components.details then
					active_components.details.set_loading(version)
					nuget.fetch_package_metadata(pkg.name, version, function(metadata)
						if active_components.details then
							active_components.details.update(metadata, version)
						end
					end)
				end
			end,
			on_enter = function()
				if active_components.details then
					reset_border_colors("details")
					active_components.details.focus()
				end
			end,
			on_tab = function()
				if active_components.details then
					reset_border_colors("details")
					active_components.details.focus()
				end
			end,
			on_close = function()
				if active_components.version_list then
					active_components.version_list.close()
					active_components.version_list = nil
				end
				if active_components.details then
					active_components.details.close()
					active_components.details = nil
				end
				expand_to_full_width()
			end,
			on_refresh = function(updated_packages)
				if active_components.package_list and updated_packages then
					active_components.package_list.update_packages(updated_packages)
				end
			end,
			on_set_loading = function(loading_message)
				if active_components.package_list then
					if loading_message then
						active_components.package_list.set_loading(loading_message)
					else
						active_components.package_list.clear_loading()
					end
				end
			end,
		})

		if not version_list then
			return
		end
		active_components.version_list = version_list

		local details = details_component.create({
			package = pkg,
			width = details_width,
			height = details_height,
			col = versions_col,
			row = versions_row + versions_height + 1 + margin,
			on_tab = function()
				if active_components.search then
					reset_border_colors("search")
					active_components.search.activate()
				end
			end,
			on_close = function()
				if active_components.version_list then
					active_components.version_list.close()
					active_components.version_list = nil
				end
				if active_components.details then
					active_components.details.close()
					active_components.details = nil
				end
				expand_to_full_width()
			end,
		})
		if not details then
			return
		end
		active_components.details = details

		nuget.fetch_package_versions(pkg.name, function(versions_array)
			if not versions_array or #versions_array == 0 then
				vim.notify("No versions found for " .. pkg.name .. " during UI init", vim.log.levels.WARN)
				return
			end

			if active_components.version_list then
				active_components.version_list.update(versions_array)
			end

			local initial_version = pkg.resolved_version
			if not initial_version and versions_array and #versions_array > 0 then
				initial_version = versions_array[#versions_array]
			end

			if initial_version and active_components.details then
				active_components.details.set_loading(initial_version)
				nuget.fetch_package_metadata(pkg.name, initial_version, function(metadata)
					if active_components.details then
						active_components.details.update(metadata, initial_version)
					end
				end)
			end
		end)

		reset_border_colors("version_list")
		active_components.version_list.focus()
	end

	local search = search_component.create({
		width = list_width,
		height = search_height,
		col = col,
		row = row,
		on_change = function(term)
			if active_components.package_list then
				active_components.package_list.update(term)
			end

			if active_components.available_package_list then
				active_components.available_package_list.update_params({ q = term })
			end
		end,
		on_enter = function()
			if active_components.package_list then
				reset_border_colors("package_list")
				active_components.package_list.focus()
			end
		end,
		on_escape = function()
			if active_components.package_list then
				active_components.package_list.focus()
			end
		end,
		on_tab = function()
			if active_components.package_list then
				reset_border_colors("package_list")
				active_components.package_list.focus()
			end
		end,
		on_close = close_all_components,
	})

	if not search then
		close_all_components()
		return nil
	end

	active_components.search = search

	local package_list = package_list_component.create({
		packages = packages or {},
		width = total_width,
		height = installed_height,
		col = col,
		row = (select(2, get_installed_pos())),
		on_select = function(pkg)
			handle_package_selection(pkg)
		end,
		on_search = function()
			if active_components.search then
				active_components.search.activate()
			end
		end,
		on_tab = function()
			if active_components.available_package_list then
				reset_border_colors("available_package_list")
				active_components.available_package_list.focus()
			elseif active_components.version_list then
				reset_border_colors("version_list")
				active_components.version_list.focus()
			elseif active_components.details then
				reset_border_colors("details")
				active_components.details.focus()
			else
				if active_components.search then
					reset_border_colors("search")
					active_components.search.activate()
				end
			end
		end,
		on_close = close_all_components,
	})

	if not package_list then
		close_all_components()
		return nil
	end

	active_components.package_list = package_list

	local available_package_list = available_package_list_component.create({
		width = total_width,
		height = available_height,
		col = col,
		row = (select(2, get_available_pos())),
		on_select = function(pkg)
			handle_package_selection(pkg)
		end,
		on_search = function()
			if active_components.search then
				active_components.search.activate()
			end
		end,
		on_tab = function()
			if active_components.version_list then
				reset_border_colors("version_list")
				active_components.version_list.focus()
			elseif active_components.details then
				reset_border_colors("details")
				active_components.details.focus()
			elseif active_components.search then
				reset_border_colors("search")
				active_components.search.activate()
			end
		end,
		on_close = close_all_components,
	})

	if not available_package_list then
		close_all_components()
		return nil
	end

	active_components.available_package_list = available_package_list

	-- Update package list with actual data if available
	if packages then
		package_list.update_packages(packages)
	end

	-- Focus search input by default
	if active_components.search then
		reset_border_colors("search")
		active_components.search.activate()
	end

	return {
		components = active_components,
		close = close_all_components,
	}
end

function M.display_package_details_split(pkg, metadata)
	if not pkg then
		vim.notify("No package provided", vim.log.levels.ERROR)
		return nil
	end

	local background = utils.create_background()

	local dimensions = utils.calculate_centered_dimensions(0.8, 0.8)
	local width = dimensions.width
	local height = dimensions.height
	local col = dimensions.col
	local row = dimensions.row

	local versions_height = math.floor(height * 0.3)
	local details_height = height - versions_height - 1

	local active_components = {
		background = background,
	}

	_G.active_components = active_components

	local function reset_border_colors(focused_component)
		for component_name, component in pairs(active_components) do
			if
				component_name ~= "background"
				and component_name ~= focused_component
				and component
				and component.win
			then
				utils.set_focused_border_color(component.win, false)
			end
		end
	end

	local function close_all_components()
		for _, component in pairs(active_components) do
			if component and component.close then
				component.close()
			end
		end
	end

	local version_list = version_list_component.create({
		package = pkg,
		width = width,
		height = versions_height,
		col = col,
		row = row,
		on_select = function(version)
			if active_components.details then
				active_components.details.set_loading(version)

				nuget.fetch_package_metadata(pkg.name, version, function(ver_metadata)
					if active_components.details then
						active_components.details.update(ver_metadata, version)
					end
				end)
			end
		end,
		on_enter = function()
			if active_components.details then
				reset_border_colors("details")
				active_components.details.focus()
			end
		end,
		on_tab = function()
			if active_components.version_list then
				reset_border_colors("version_list")
				active_components.version_list.focus()
			end
		end,
		on_close = close_all_components,
	})

	if not version_list then
		background.close()
		return nil
	end

	active_components.version_list = version_list

	local details = details_component.create({
		package = pkg,
		width = width,
		height = details_height,
		col = col,
		row = row + versions_height + 1,
		on_tab = function()
			if active_components.version_list then
				reset_border_colors("version_list")
				active_components.version_list.focus()
			end
		end,
		on_close = close_all_components,
	})

	if not details then
		close_all_components()
		return nil
	end

	active_components.details = details

	if metadata then
		details.update(metadata, pkg.resolved_version)
	end

	nuget.fetch_package_versions(pkg.name, function(versions_array)
		if not versions_array or #versions_array == 0 then
			vim.notify("No versions found for " .. pkg.name .. " during UI init", vim.log.levels.WARN)
			return
		end

		if active_components.version_list then
			active_components.version_list.update(versions_array)
		end

		local initial_version = pkg.resolved_version
		if not initial_version and versions_array and #versions_array > 0 then
			initial_version = versions_array[#versions_array]
		end

		if initial_version and active_components.details and not metadata then
			active_components.details.set_loading(initial_version)
			nuget.fetch_package_metadata(pkg.name, initial_version, function(metadata)
				if active_components.details then
					active_components.details.update(metadata, initial_version)
				end
			end)
		end
	end)

	return {
		components = active_components,
		close = close_all_components,
	}
end

M.create_buffer = utils.create_buffer

return M
