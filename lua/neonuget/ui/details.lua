local utils = require("neonuget.ui.utils")
local baseui = require("neonuget.ui.baseui")

local function split_lines_robust(str)
	if not str then
		return {}
	end
	local normalized_str = str:gsub("\r\n", "\n"):gsub("\r", "\n")
	local lines = {}
	local start = 1
	while true do
		local nl_pos = normalized_str:find("\n", start, true)
		if nl_pos then
			table.insert(lines, normalized_str:sub(start, nl_pos - 1))
			start = nl_pos + 1
		else
			table.insert(lines, normalized_str:sub(start))
			break
		end
	end
	return lines
end

local M = {}

function M.create(opts)
	opts = opts or {}
	local pkg = opts.package
	local version = opts.version or (pkg and pkg.resolved_version)
	local width = opts.width or 40
	local height = opts.height or 20
	local col = opts.col or 0
	local row = opts.row or 0

	if not pkg then
		vim.notify("No package provided for details view", vim.log.levels.ERROR)
		return nil
	end

	local update_with_metadata
	local set_loading_state

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

	local initial_content = {
		"Loading package details...",
	}

	local title = "Details: " .. pkg.name

	local component = baseui.create_component({
		title = title,
		width = width,
		height = height,
		col = col,
		row = row,
		buffer_name = "NuGet_Package_Details_" .. pkg.name,
		initial_content = initial_content,
		wrap = true,
		cursorline = false,
		filetype = "markdown",
		focus = false,
		mappings = {},
	})

	if not component then
		return nil
	end

	utils.set_buffer_mappings(component.buf, {
		n = {
			["<Tab>"] = handle_tab,
			["q"] = handle_close,
			["<Esc>"] = handle_close,
		},
	})

	utils.setup_section_navigation(component.buf)

	update_with_metadata = function(metadata, version)
		if not component.buf or not vim.api.nvim_buf_is_valid(component.buf) then
			return
		end

		local buf = component.buf

		if component.win and vim.api.nvim_win_is_valid(component.win) and version then
			component.set_title("Details: " .. pkg.name)
		end

		if not metadata then
			vim.notify("Received nil metadata for " .. pkg.name, vim.log.levels.ERROR)
			vim.api.nvim_buf_set_option(buf, "modifiable", true)
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Failed to load details for " .. pkg.name })
			vim.api.nvim_buf_set_option(buf, "modifiable", false)
			return
		end

		local catalog_entry = metadata.catalogEntry
		local content = {}
		local highlights = {}
		local namespace_id = vim.api.nvim_create_namespace("neonuget_details_labels")

		local function add_section(label, value)
			if value and value ~= "" then
				local line_num = #content
				table.insert(content, label .. ":")
				table.insert(content, value)
				table.insert(content, "")
				table.insert(highlights, { line = line_num, group = "NuGetDetailsLabel" })
			else
				local line_num = #content
				table.insert(content, label .. ":")
				table.insert(content, "Unknown")
				table.insert(content, "")
				table.insert(highlights, { line = line_num, group = "NuGetDetailsLabel" })
			end
		end

		local function add_description(value)
			local line_num = #content
			table.insert(content, "Description:")
			table.insert(highlights, { line = line_num, group = "NuGetDetailsLabel" })

			if value and value ~= "" then
				local description_lines = split_lines_robust(value)
				for _, line in ipairs(description_lines) do
					local trimmed_line = line:match("^%s*(.-)%s*$")
					table.insert(content, trimmed_line or "")
				end
			else
				table.insert(content, "No description available.")
			end
			table.insert(content, "")
		end

		local description = metadata.description
		if (not description or description == "") and catalog_entry then
			description = catalog_entry.description
		end
		add_description(description)

		local authors = metadata.authors
		if (not authors or authors == "") and catalog_entry then
			authors = catalog_entry.authors
		end
		add_section("Authors", authors)

		local published = metadata.published
		if (not published or published == "") and catalog_entry then
			published = catalog_entry.published
		end

		local published_date_str = "Unknown"
		if published and published ~= "" then
			local year, month, day = published:match("(%d+)-(%d+)-(%d+)")
			if year and month and day then
				published_date_str = year .. "-" .. month .. "-" .. day
			end
		end
		add_section("Published", published_date_str)

		local tags = metadata.tags
		if (not tags or (type(tags) == "table" and #tags == 0)) and catalog_entry then
			tags = catalog_entry.tags
		end

		local tags_str = ""
		if tags and type(tags) == "table" and #tags > 0 then
			tags_str = table.concat(tags, ", ")
		elseif tags and type(tags) == "string" and tags ~= "" then
			tags_str = tags
		end
		if tags_str ~= "" then
			add_section("Tags", tags_str)
		end

		local project_url = metadata.projectUrl
		if (not project_url or project_url == "") and catalog_entry then
			project_url = catalog_entry.projectUrl
		end
		add_section("Project", project_url)

		local license_url = metadata.licenseUrl
		if (not license_url or license_url == "") and catalog_entry then
			license_url = catalog_entry.licenseUrl
		end
		add_section("License", license_url)

		local download_count = metadata.totalDownloads
		if (not download_count or download_count == 0) and catalog_entry then
			download_count = catalog_entry.totalDownloads or catalog_entry.downloadCount
		end
		if download_count and download_count > 0 then
			add_section("Total Downloads", tostring(download_count))
		end

		local dependencies = metadata.dependencies
		if (not dependencies or (type(dependencies) == "table" and #dependencies == 0)) and catalog_entry then
			dependencies = catalog_entry.dependencyGroups
		end

		if dependencies and type(dependencies) == "table" and #dependencies > 0 then
			local line_num = #content
			table.insert(content, "Dependencies:")
			table.insert(highlights, { line = line_num, group = "NuGetDetailsLabel" })

			for _, dep_group in ipairs(dependencies) do
				local framework = dep_group.targetFramework or "Any"
				if dep_group.dependencies and #dep_group.dependencies > 0 then
					table.insert(content, "  Framework: " .. framework)
					for _, dep in ipairs(dep_group.dependencies) do
						local dep_str = "    - " .. dep.id
						if dep.range and dep.range ~= "" then
							dep_str = dep_str .. " (" .. dep.range .. ")"
						end
						table.insert(content, dep_str)
					end
				end
			end
			table.insert(content, "")
		end

		vim.api.nvim_buf_set_option(buf, "modifiable", true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
		vim.api.nvim_buf_set_option(buf, "modifiable", false)

		vim.api.nvim_buf_clear_namespace(buf, namespace_id, 0, -1)

		for _, hl in ipairs(highlights) do
			vim.api.nvim_buf_add_highlight(buf, namespace_id, hl.group, hl.line, 0, -1)
		end
	end

	set_loading_state = function(version)
		if not component.buf or not vim.api.nvim_buf_is_valid(component.buf) then
			return
		end

		if component.win and vim.api.nvim_win_is_valid(component.win) and version then
			component.set_title("Details: " .. pkg.name)
		end

		vim.api.nvim_buf_set_option(component.buf, "modifiable", true)
		vim.api.nvim_buf_set_lines(component.buf, 0, -1, false, {
			"Loading details...",
		})
		vim.api.nvim_buf_set_option(component.buf, "modifiable", false)
	end

	component.update = update_with_metadata
	component.set_loading = set_loading_state

	return component
end

return M
