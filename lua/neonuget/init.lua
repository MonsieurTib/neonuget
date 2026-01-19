local nuget = require("neonuget.nuget")
local ui = require("neonuget.ui")
local ftplugin = require("neonuget.ftplugin")

local M = {}

M._current_active_project = nil -- Stores the project path selected by the user for the current UI session

M.config = {
	dotnet_path = "dotnet",
	default_project = nil,
}

function M.setup(opts)
	if opts then
		M.config = vim.tbl_deep_extend("force", M.config, opts)
	end

	ftplugin.setup()

	
	local group = vim.api.nvim_create_augroup("NeoNuGetHighlights", { clear = true })
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = group,
		pattern = "*",
		callback = function()
			vim.api.nvim_set_hl(0, "NuGetDetailsLabel", { fg = "#34B3FA", bold = true })
			vim.api.nvim_set_hl(0, "NuGetUpdateAvailable", { fg = "#A6E3A1", bold = true })
		end,
	})

	
	pcall(vim.api.nvim_set_hl, 0, "NuGetDetailsLabel", { fg = "#34B3FA", bold = true })
	pcall(vim.api.nvim_set_hl, 0, "NuGetUpdateAvailable", { fg = "#A6E3A1", bold = true })

	vim.api.nvim_create_user_command("NuGet", function()
		if ui.is_open() then
			ui.close()
		else
			M.list_packages()
		end
	end, {})
end

function M._get_active_project_or_notify()
	if M._current_active_project and M._current_active_project ~= "" then
		return M._current_active_project
	end

	local project_path = M.config.default_project or M._find_project()
	if not project_path then
		vim.notify("No active .NET project. Please run :NuGet first or set `default_project`.", vim.log.levels.ERROR)
		return nil
	end
	return project_path
end

function M.list_packages()
	local active_project_path = M.config.default_project

	if not active_project_path then
		local all_projects = M._find_all_projects()

		if #all_projects == 0 then
			vim.notify("No .NET project found in the workspace.", vim.log.levels.ERROR)
			M._current_active_project = nil
			return
		elseif #all_projects == 1 then
			active_project_path = all_projects[1]
		else
			-- Multiple projects, prompt user
			vim.ui.select(all_projects, { prompt = "Select a project:" }, function(choice)
				if not choice then
					vim.notify("Project selection cancelled.", vim.log.levels.INFO)
					M._current_active_project = nil
					return
				end
				M._current_active_project = choice
				M._list_packages_for_project(choice)
			end)
			return
		end
	end

	M._current_active_project = active_project_path
	M._list_packages_for_project(active_project_path)
end

function M._list_packages_for_project(project_path)
	-- Show UI immediately with loading states
	local windows = ui.display_dual_pane({}, { project_path = project_path })
	if not windows then
		vim.notify("Failed to create package viewer interface", vim.log.levels.ERROR)
		return
	end

	-- Fetch packages in the background
	M.refresh_packages(function(packages)
		local packages_to_display = packages or {}
		if windows and windows.components and windows.components.package_list then
			windows.components.package_list.update_packages(packages_to_display)
		end
	end, project_path)
end

function M._find_all_projects()
	local projects = {}
	local patterns = { "*.csproj", "*.fsproj", "*.vbproj" }
	local search_paths = { ".", "./*", "./*/*" }

	for _, search_path_prefix in ipairs(search_paths) do
		for _, pattern in ipairs(patterns) do
			local glob_pattern = search_path_prefix .. "/" .. pattern
			local found_files = vim.fn.globpath(".", glob_pattern, true, true, true)
			for _, file_path in ipairs(found_files) do
				local normalized_path = vim.fn.fnamemodify(file_path, ":.")
				local already_added = false
				for _, existing_proj in ipairs(projects) do
					if existing_proj == normalized_path then
						already_added = true
						break
					end
				end
				if not already_added and normalized_path ~= "" then
					table.insert(projects, normalized_path)
				end
			end
		end
	end
	return projects
end

function M._find_project()
	local handle = io.popen("find . -maxdepth 2 -name '*.csproj' -o -name '*.fsproj' -o -name '*.vbproj'")
	if not handle then
		return nil
	end

	local result = handle:read("*a")
	handle:close()

	local project_file = result:match("(.-)\n")
	return project_file
end

function M._execute_command(command, callback)
	local stdout_data = {}
	local stderr_data = {}

	local job_id = vim.fn.jobstart(command, {
		on_stdout = function(_, data)
			if data and #data > 0 then
				if data[#data] == "" then
					table.remove(data, #data)
				end

				for _, line in ipairs(data) do
					table.insert(stdout_data, line)
				end
			end
		end,
		on_stderr = function(_, data)
			if data and #data > 0 then
				if data[#data] == "" then
					table.remove(data, #data)
				end

				for _, line in ipairs(data) do
					table.insert(stderr_data, line)
				end
			end
		end,
		on_exit = function(_, exitcode)
			if callback then
				callback(exitcode, stdout_data, stderr_data)
			end
		end,
	})

	if job_id <= 0 then
		vim.notify("Failed to start command: " .. command, vim.log.levels.ERROR)
		if callback then
			callback(-1, {}, { "Failed to start job" })
		end
	end
end

function M.install_package(pkg_name, version, callback)
	local project_path = M._get_active_project_or_notify()
	if not project_path then
		if callback then
			callback(false)
		end
		return
	end

	local command = M.config.dotnet_path .. " add \"" .. project_path .. "\" package " .. pkg_name
	if version then
		command = command .. " --version " .. version
	end

	M._execute_command(command, function(exitcode, _, stderr_data)
		if exitcode ~= 0 then
			local err_msg = table.concat(stderr_data, "\n")
			vim.notify(
				"Package installation failed: " .. (err_msg ~= "" and err_msg or "Exit code: " .. exitcode),
				vim.log.levels.ERROR
			)
			if callback then
				callback(false)
			end
		else
			if callback then
				callback(true)
			end
		end
	end)
end

local function _restore_project(project_path, callback)
	local restore_command = M.config.dotnet_path .. " restore \"" .. project_path .. "\""
	M._execute_command(restore_command, function(exitcode, _, stderr_data)
		if exitcode ~= 0 then
			local err_msg = table.concat(stderr_data, "\n")
			vim.notify(
				"Failed to restore project dependencies: " .. (err_msg ~= "" and err_msg or "Exit code: " .. exitcode),
				vim.log.levels.ERROR
			)
			if callback then
				callback(false)
			end
			return
		end

		if callback then
			callback(true)
		end
	end)
end

function M.uninstall_package(pkg_name, callback)
	local project_path = M._get_active_project_or_notify()
	if not project_path then
		if callback then
			callback(false)
		end
		return false
	end

	local command = M.config.dotnet_path .. " remove \"" .. project_path .. "\" package " .. pkg_name

	M._execute_command(command, function(exitcode, _, stderr_data)
		if exitcode ~= 0 then
			local err_msg = table.concat(stderr_data, "\n")
			vim.notify(
				"Package uninstallation failed: " .. (err_msg ~= "" and err_msg or "Exit code: " .. exitcode),
				vim.log.levels.ERROR
			)
			if callback then
				callback(false)
			end
			return
		end

		vim.defer_fn(function()
			_restore_project(project_path, function(restore_ok)
				if not restore_ok then
					if callback then
						callback(true, nil)
					end
					return
				end

				vim.defer_fn(function()
					M.refresh_packages(function(refreshed_packages)
						if callback then
							callback(true, refreshed_packages)
						end
					end)
				end, 500)
			end)
		end, 500)
	end)

	return true
end

function M.refresh_packages(callback, project_path_override)
	local project_path = project_path_override
	if not project_path then
		project_path = M._get_active_project_or_notify()
		if not project_path then
			if callback then
				callback(nil)
			end
			return
		end
	elseif project_path == "" then
		vim.notify("Provided project path for refresh is invalid.", vim.log.levels.ERROR)
		if callback then
			callback(nil)
		end
		return
	end

	-- Command 1: Get ALL installed packages
	local list_all_command = M.config.dotnet_path .. " list \"" .. project_path .. "\" package --include-transitive --format json"

	M._execute_command(list_all_command, function(exitcode_all, output_all, stderr_all)
		if exitcode_all ~= 0 then
			local err_msg_all = table.concat(stderr_all, "\n")
			vim.notify(
				"Failed to list all packages: " .. (err_msg_all ~= "" and err_msg_all or "Exit code: " .. exitcode_all),
				vim.log.levels.ERROR
			)
			if callback then
				callback(nil)
			end
			return
		end

		if not output_all or #output_all == 0 then
			vim.notify("No output received from list all packages command.", vim.log.levels.ERROR)
			if callback then
				callback(nil)
			end
			return
		end

		local json_str_all = table.concat(output_all, "")
		local parse_all_ok, all_installed_packages_result = pcall(nuget.parse_json_package_list, json_str_all)

		if not parse_all_ok then
			vim.notify("Failed to parse list of all packages: " .. tostring(all_installed_packages_result), vim.log.levels.ERROR)
			if callback then
				callback(nil)
			end
			return
		end

		if not all_installed_packages_result then
			vim.notify("Parsed list of all packages is unexpectedly nil.", vim.log.levels.ERROR)
			if callback then
				callback(nil)
			end
			return
		end

		-- Command 2: Get OUTDATED packages (for accurate latestVersion)
		local list_outdated_command = M.config.dotnet_path .. " list \"" .. project_path .. "\" package --outdated --format json" -- No --include-transitive needed here, we only care about top-level latest versions.
		M._execute_command(list_outdated_command, function(exitcode_outdated, output_outdated, stderr_outdated)
			local outdated_packages_info = {} -- Store as a lookup table: { ["Package.Name"] = "LatestVersion", ... }

			if exitcode_outdated == 0 and output_outdated and #output_outdated > 0 then
				local json_str_outdated = table.concat(output_outdated, "")
				local parse_outdated_ok, parsed_outdated_list = pcall(nuget.parse_json_package_list, json_str_outdated)

				if parse_outdated_ok and parsed_outdated_list then
					for _, pkg_outdated in ipairs(parsed_outdated_list) do
						if pkg_outdated.name and pkg_outdated.latest_version and pkg_outdated.latest_version ~= "" then
							outdated_packages_info[pkg_outdated.name] = pkg_outdated.latest_version
						end
					end
				else
					if not parse_outdated_ok then
						vim.notify("Failed to parse outdated package list: " .. tostring(parsed_outdated_list) .. ". Update indicators may be inaccurate.", vim.log.levels.WARN)
					else
						vim.notify("Problem parsing outdated package list or no outdated packages found. Update indicators may be inaccurate.", vim.log.levels.INFO)
					end
				end
			else
				local err_msg_outdated = table.concat(stderr_outdated or {}, "\n")
				vim.notify(
					"Failed to fetch outdated package details (" .. (err_msg_outdated ~= "" and err_msg_outdated or "Exit code: " .. exitcode_outdated) .. "). Update indicators may be inaccurate.",
					vim.log.levels.WARN
				)
			end

			for _, pkg_installed in ipairs(all_installed_packages_result) do
				if outdated_packages_info[pkg_installed.name] then
					pkg_installed.latest_version = outdated_packages_info[pkg_installed.name]
				else
					pkg_installed.latest_version = pkg_installed.resolved_version
				end
			end

			if callback then
				callback(all_installed_packages_result)
			end
		end)
	end)
	return true
end

return M
