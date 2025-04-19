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

		add_description(metadata.description)
		add_section("Authors", metadata.authors)

		local published_date_str = "Unknown"
		if metadata.published and metadata.published ~= "" then
			local year, month, day = metadata.published:match("(%d+)-(%d+)-(%d+)")
			if year and month and day then
				published_date_str = year .. "-" .. month .. "-" .. day
			end
		end
		add_section("Published", published_date_str)

		local tags_str = ""
		if metadata.tags and type(metadata.tags) == "table" and #metadata.tags > 0 then
			tags_str = table.concat(metadata.tags, ", ")
		elseif metadata.tags and type(metadata.tags) == "string" and metadata.tags ~= "" then
			tags_str = metadata.tags
		end
		if tags_str ~= "" then
			add_section("Tags", tags_str)
		end

		add_section("Project", metadata.projectUrl)
		add_section("License", metadata.licenseUrl)

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
