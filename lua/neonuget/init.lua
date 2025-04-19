local nuget = require("neonuget.nuget")
local ui = require("neonuget.ui")
local ftplugin = require("neonuget.ftplugin")

local M = {}

M.config = {
	dotnet_path = "dotnet",
	default_project = nil,
}

function M.setup(opts)
	if opts then
		M.config = vim.tbl_deep_extend("force", M.config, opts)
	end

	ftplugin.setup()

	vim.api.nvim_create_user_command("NuGet", function()
		M.list_packages()
	end, {})
end

function M._get_project_or_notify()
	local project_path = M.config.default_project or M._find_project()
	if not project_path then
		vim.notify("No .NET project found. Please specify a project path with :NuGetSetProject", vim.log.levels.ERROR)
		return nil
	end
	return project_path
end

function M.list_packages()
	M.refresh_packages(function(packages)
		if packages == nil then
			return
		end

		if #packages == 0 then
			vim.notify("No packages found in the project.", vim.log.levels.WARN)
			return
		end

		local windows = ui.display_dual_pane(packages, {})
		if not windows then
			vim.notify("Failed to create package viewer interface", vim.log.levels.ERROR)
			return
		end
	end)
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
	local project_path = M._get_project_or_notify()
	if not project_path then
		if callback then
			callback(false)
		end
		return
	end

	local command = M.config.dotnet_path .. " add " .. project_path .. " package " .. pkg_name
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
	local restore_command = M.config.dotnet_path .. " restore " .. project_path
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
	local project_path = M._get_project_or_notify()
	if not project_path then
		if callback then
			callback(false)
		end
		return false
	end

	local command = M.config.dotnet_path .. " remove " .. project_path .. " package " .. pkg_name

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

function M.refresh_packages(callback)
	local project_path = M._get_project_or_notify()
	if not project_path then
		if callback then
			callback(nil)
		end
		return
	end

	local command = M.config.dotnet_path .. " list " .. project_path .. " package --include-transitive --format json"
	M._execute_command(command, function(exitcode, output, stderr_data)
		if exitcode ~= 0 then
			local err_msg = table.concat(stderr_data, "\n")
			vim.notify(
				"Failed to refresh packages: " .. (err_msg ~= "" and err_msg or "Exit code: " .. exitcode),
				vim.log.levels.ERROR
			)
			if callback then
				callback(nil)
			end
			return
		end

		if not output or #output == 0 then
			vim.notify("No output received from dotnet list package command.", vim.log.levels.ERROR)
			if callback then
				callback(nil)
			end
			return
		end

		local json_str = table.concat(output, "")

		local ok, packages = pcall(function()
			return nuget.parse_json_package_list(json_str)
		end)

		if not ok then
			vim.notify("Failed to parse package list: " .. tostring(packages), vim.log.levels.ERROR)
			if callback then
				callback(nil)
			end
			return
		end

		if not packages then
			vim.notify("No packages found in the project.", vim.log.levels.WARN)
			if callback then
				callback({})
			end
			return
		end

		if callback then
			callback(packages)
		end
	end)
end

return M
