local M = {}

function M.create_buffer(name)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(buf, "modifiable", true)
	vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(buf, "swapfile", false)
	vim.api.nvim_buf_set_option(buf, "filetype", "neonuget")

	if name then
		local unique_id = os.time()
		local unique_name = string.format("%s_%s", name, unique_id)

		local ok, err = pcall(function()
			vim.api.nvim_buf_set_name(buf, unique_name)
		end)

		if not ok then
			vim.notify("Warning: Could not set buffer name. " .. tostring(err), vim.log.levels.WARN)
		end
	end

	return buf
end

function M.configure_window(win, options)
	if not win or not vim.api.nvim_win_is_valid(win) then
		return
	end

	for option, value in pairs(options) do
		vim.api.nvim_win_set_option(win, option, value)
	end
end

function M.set_buffer_mappings(buf, mappings)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	for mode, mode_mappings in pairs(mappings) do
		for key, mapping in pairs(mode_mappings) do
			vim.api.nvim_buf_set_keymap(buf, mode, key, "", {
				noremap = true,
				silent = true,
				callback = mapping,
			})
		end
	end
end

function M.create_background()
	local background_buf = M.create_buffer("NuGet_Background")
	vim.cmd([[highlight NuGetBg guibg=#000000 guifg=NONE blend=30]])

	vim.api.nvim_buf_set_option(background_buf, "modifiable", true)
	local bg_lines = {}
	for _ = 1, vim.o.lines do
		table.insert(bg_lines, string.rep(" ", vim.o.columns))
	end
	vim.api.nvim_buf_set_lines(background_buf, 0, -1, false, bg_lines)
	vim.api.nvim_buf_set_option(background_buf, "modifiable", false)

	local background_win = vim.api.nvim_open_win(background_buf, false, {
		relative = "editor",
		width = vim.o.columns,
		height = vim.o.lines,
		col = 0,
		row = 0,
		style = "minimal",
		focusable = false,
		zindex = 10,
	})

	if background_win and vim.api.nvim_win_is_valid(background_win) then
		vim.api.nvim_win_set_option(background_win, "winblend", 30)
		vim.api.nvim_win_set_option(background_win, "winhighlight", "Normal:NuGetBg")
	end

	return {
		buf = background_buf,
		win = background_win,
		close = function()
			if background_win and vim.api.nvim_win_is_valid(background_win) then
				vim.api.nvim_win_close(background_win, true)
			end
		end,
	}
end

function M.calculate_centered_dimensions(width_percent, height_percent)
	local width = math.min(math.floor(vim.o.columns * (width_percent or 0.8)), vim.o.columns - 4)
	local height = math.min(math.floor(vim.o.lines * (height_percent or 0.8)), vim.o.lines - 4)
	local col = math.floor((vim.o.columns - width) / 2)
	local row = math.floor((vim.o.lines - height) / 2)

	return {
		width = width,
		height = height,
		col = col,
		row = row,
	}
end

function M.close_windows_by_pattern(patterns)
	patterns = patterns or {}
	local windows_to_close = {}

	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		local name = vim.api.nvim_buf_get_name(buf)

		for _, pattern in ipairs(patterns) do
			if name:match(pattern) then
				table.insert(windows_to_close, win)
				break
			end
		end
	end

	for _, win in ipairs(windows_to_close) do
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end
end

function M.setup_highlights()
	vim.api.nvim_set_hl(0, "NuGetFocusedBorder", { fg = "#F9B387", bold = true, sp = "#F9B387" })
	vim.api.nvim_set_hl(0, "NuGetDetailsLabel", { bold = true })
end

function M.set_focused_border_color(win, focused)
	if not win or not vim.api.nvim_win_is_valid(win) then
		return
	end
	if focused then
		vim.api.nvim_win_set_option(win, "winhl", "NormalFloat:Normal,FloatBorder:NuGetFocusedBorder")
	else
		vim.api.nvim_win_set_option(win, "winhl", "")
	end
end

-- Section navigation mapping: number key -> component name
M.section_mappings = {
	["1"] = "search",
	["2"] = "package_list",
	["3"] = "available_package_list",
	["4"] = "version_list",
	["5"] = "details",
}

function M.focus_section(component_name)
	local active_components = _G.active_components
	if not active_components then
		return false
	end

	local component = active_components[component_name]
	if not component or not component.win or not vim.api.nvim_win_is_valid(component.win) then
		return false
	end

	for name, comp in pairs(active_components) do
		if name ~= "background" and comp and comp.win and vim.api.nvim_win_is_valid(comp.win) then
			M.set_focused_border_color(comp.win, false)
		end
	end

	M.set_focused_border_color(component.win, true)
	if component.focus then
		component.focus()
	elseif component.activate then
		component.activate()
	else
		vim.api.nvim_set_current_win(component.win)
	end

	return true
end

-- Set up section navigation keymaps on a buffer
function M.setup_section_navigation(buf)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	for key, component_name in pairs(M.section_mappings) do
		vim.api.nvim_buf_set_keymap(buf, "n", key, "", {
			noremap = true,
			silent = true,
			callback = function()
				M.focus_section(component_name)
			end,
		})
	end
end

return M
