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

	local resize_augroup = vim.api.nvim_create_augroup("NuGetResize", { clear = true })

	local function close_all_components()
		vim.api.nvim_clear_autocmds({ group = resize_augroup })

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

	local function recalculate_layout()
		local dims = utils.calculate_centered_dimensions(0.8, 0.8)
		local tw = dims.width
		local th = dims.height
		local c = dims.col
		local r = dims.row

		local m = 2
		local lw = math.floor(tw * 0.4)
		local dw = tw - lw - 1 - m
		local sh = 1
		local vh = math.floor(th * 0.3)
		local dh = th - vh - 1 - m
		local rph = vh + dh + 1 + m
		local lph = rph
		local lch = lph - sh - m * 2 - 2
		local ih = math.floor(lch * 0.5)
		local ah = lch - ih

		return {
			total_width = tw,
			total_height = th,
			col = c,
			row = r,
			margin = m,
			list_width = lw,
			details_width = dw,
			search_height = sh,
			versions_height = vh,
			details_height = dh,
			installed_height = ih,
			available_height = ah,
			search_col = c,
			search_row = r,
			installed_col = c,
			installed_row = r + sh + 1 + m,
			available_col = c,
			available_row = r + sh + 1 + m + ih + m + 1,
			versions_col = c + lw + 1 + m,
			versions_row = r,
			details_col = c + lw + 1 + m,
			details_row = r + vh + 1 + m,
		}
	end

	local function resize_all_components()
		local layout = recalculate_layout()

		if active_components.background and active_components.background.resize then
			active_components.background.resize()
		end

		local has_right_pane = active_components.version_list ~= nil or active_components.details ~= nil
		local list_pane_width = has_right_pane and layout.list_width or layout.total_width

		if active_components.search then
			active_components.search.resize(layout.list_width, layout.search_height, layout.search_col, layout.search_row)
		end

		if active_components.package_list then
			active_components.package_list.resize(list_pane_width, layout.installed_height, layout.installed_col, layout.installed_row)
		end

		if active_components.available_package_list then
			active_components.available_package_list.resize(list_pane_width, layout.available_height, layout.available_col, layout.available_row)
		end

		if active_components.version_list then
			active_components.version_list.resize(layout.details_width, layout.versions_height, layout.versions_col, layout.versions_row)
		end

		if active_components.details then
			active_components.details.resize(layout.details_width, layout.details_height, layout.details_col, layout.details_row)
		end
	end

	vim.api.nvim_create_autocmd("VimResized", {
		group = resize_augroup,
		callback = resize_all_components,
	})

	local function expand_to_full_width()
		local layout = recalculate_layout()

		if active_components.search then
			active_components.search.resize(layout.list_width, layout.search_height, layout.search_col, layout.search_row)
		end

		if active_components.package_list then
			active_components.package_list.resize(layout.total_width, layout.installed_height, layout.installed_col, layout.installed_row)
		end

		if active_components.available_package_list then
			active_components.available_package_list.resize(layout.total_width, layout.available_height, layout.available_col, layout.available_row)
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

		local layout = recalculate_layout()

		if active_components.package_list then
			active_components.package_list.resize(layout.list_width, layout.installed_height, layout.installed_col, layout.installed_row)
		end
		if active_components.available_package_list then
			active_components.available_package_list.resize(layout.list_width, layout.available_height, layout.available_col, layout.available_row)
		end
		if active_components.search then
			active_components.search.resize(layout.list_width, layout.search_height, layout.search_col, layout.search_row)
		end

		local version_list = version_list_component.create({
			package = pkg,
			width = layout.details_width,
			height = layout.versions_height,
			col = layout.versions_col,
			row = layout.versions_row,
			on_select = function(version, metadata)
				if active_components.details then
					active_components.details.set_loading(version)

					if metadata then
						active_components.details.update(metadata, version)
					else
						nuget.fetch_package_metadata(pkg.name, version, function(api_metadata)
							if active_components.details then
								active_components.details.update(api_metadata, version)
							end
						end)
					end
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
			width = layout.details_width,
			height = layout.details_height,
			col = layout.details_col,
			row = layout.details_row,
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

		nuget.fetch_all_package_versions(pkg.name, function(versions_array)
			if not versions_array or #versions_array == 0 then
				vim.notify("No versions found for " .. pkg.name .. " during UI init", vim.log.levels.WARN)
				return
			end

			local version_info_map = {}
			for _, version_info in ipairs(versions_array) do
				version_info_map[version_info.version] = version_info
			end

			if active_components.version_list then
				active_components.version_list.version_info_map = version_info_map
			end

			if active_components.version_list then
				active_components.version_list.update(versions_array)
			end

			local initial_version = pkg.resolved_version
			if not initial_version and #versions_array > 0 then
				initial_version = versions_array[1].version
			end

			if initial_version and active_components.details then
				active_components.details.set_loading(initial_version)
				local metadata = version_info_map[initial_version]
				if metadata then
					active_components.details.update(metadata, initial_version)
				end
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
		params = {
			q = "",
			take = 50,
			prerelease = false,
			semVerLevel = "2.0.0",
			skip = 0,
			sortBy = "relevance",
		},
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

	if packages then
		package_list.update_packages(packages)
	end

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

	local resize_augroup = vim.api.nvim_create_augroup("NuGetResizeSplit", { clear = true })

	local function close_all_components()
		vim.api.nvim_clear_autocmds({ group = resize_augroup })

		for _, component in pairs(active_components) do
			if component and component.close then
				component.close()
			end
		end
	end

	local function resize_all_components()
		local dims = utils.calculate_centered_dimensions(0.8, 0.8)
		local w = dims.width
		local h = dims.height
		local c = dims.col
		local r = dims.row
		local vh = math.floor(h * 0.3)
		local dh = h - vh - 1

		if active_components.background and active_components.background.resize then
			active_components.background.resize()
		end

		if active_components.version_list then
			active_components.version_list.resize(w, vh, c, r)
		end

		if active_components.details then
			active_components.details.resize(w, dh, c, r + vh + 1)
		end
	end

	vim.api.nvim_create_autocmd("VimResized", {
		group = resize_augroup,
		callback = resize_all_components,
	})

	local version_list = version_list_component.create({
		package = pkg,
		width = width,
		height = versions_height,
		col = col,
		row = row,
		on_select = function(version, metadata)
			if active_components.details then
				active_components.details.set_loading(version)

				if metadata then
					active_components.details.update(metadata, version)
				else
					nuget.fetch_package_metadata(pkg.name, version, function(ver_metadata)
						if active_components.details then
							active_components.details.update(ver_metadata, version)
						end
					end)
				end
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

	nuget.fetch_all_package_versions(pkg.name, function(versions_array)
		if not versions_array or #versions_array == 0 then
			vim.notify("No versions found for " .. pkg.name .. " during UI init", vim.log.levels.WARN)
			return
		end

		local version_info_map = {}
		for _, version_info in ipairs(versions_array) do
			version_info_map[version_info.version] = version_info
		end

		if active_components.version_list then
			active_components.version_list.version_info_map = version_info_map
		end

		if active_components.version_list then
			active_components.version_list.update(versions_array)
		end

		local initial_version = pkg.resolved_version
		if not initial_version and #versions_array > 0 then
			initial_version = versions_array[1].version -- Newest version first
		end

		if initial_version and active_components.details and not metadata then
			active_components.details.set_loading(initial_version)

			local version_metadata = version_info_map[initial_version]
			if version_metadata then
				active_components.details.update(version_metadata, initial_version)
			end
		end
	end)

	return {
		components = active_components,
		close = close_all_components,
	}
end

M.create_buffer = utils.create_buffer

return M
