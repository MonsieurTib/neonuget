local M = {}

local utils = require("neonuget.ui.utils")

function M.create_component(opts)
	local component = {}
	opts = opts or {}
	local title = opts.title or "NuGet"
	local width = opts.width or 30
	local height = opts.height or 20
	local col = opts.col or 0
	local row = opts.row or 0
	local buffer_name = opts.buffer_name or "NuGet_Component"
	local zindex = opts.zindex or 50

	local buf = utils.create_buffer(buffer_name)
	if not buf then
		vim.notify("Failed to create buffer: " .. buffer_name, vim.log.levels.ERROR)
		return nil
	end
	if opts.initial_content then
		vim.api.nvim_buf_set_option(buf, "modifiable", true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, opts.initial_content)
		vim.api.nvim_buf_set_option(buf, "modifiable", false)
	end
	local win = nil
	local win_ok, win_err = pcall(function()
		win = vim.api.nvim_open_win(buf, opts.focus or false, {
			relative = "editor",
			width = width,
			height = height,
			col = col,
			row = row,
			border = "rounded",
			title = " " .. title .. " ",
			title_pos = "center",
			style = "minimal",
			zindex = zindex,
		})
	end)
	if not win_ok then
		vim.notify("Error creating window: " .. tostring(win_err), vim.log.levels.ERROR)
		return nil
	end
	utils.configure_window(win, {
		number = false,
		relativenumber = false,
		signcolumn = "no",
		foldcolumn = "0",
		scrolloff = 5,
		sidescrolloff = 5,
		wrap = opts.wrap or false,
		cursorline = opts.cursorline or true,
	})
	vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
	if opts.filetype then
		vim.api.nvim_buf_set_option(buf, "filetype", opts.filetype)
	end
	component.buf = buf
	component.win = win
	component.title = title

	component.focus = function()
		if win and vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_set_current_win(win)
			utils.configure_window(win, {
				number = false,
				relativenumber = false,
				signcolumn = "no",
				foldcolumn = "0",
				scrolloff = 5,
				sidescrolloff = 5,
				wrap = opts.wrap or false,
				cursorline = opts.cursorline or true,
			})
			utils.set_focused_border_color(win, true)
			vim.cmd("redraw")
		end
	end
	component.close = function()
		if win and vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end
	component.resize = function(new_width, new_height, new_col, new_row)
		if win and vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_set_config(win, {
				relative = "editor",
				width = new_width,
				height = new_height,
				col = new_col,
				row = new_row,
				title = " " .. title .. " ",
				title_pos = "center",
			})
		end
	end

	component.set_lines = function(lines, start_line, end_line)
		if buf and vim.api.nvim_buf_is_valid(buf) then
			start_line = start_line or 0
			end_line = end_line or -1

			vim.api.nvim_buf_set_option(buf, "modifiable", true)
			vim.api.nvim_buf_set_lines(buf, start_line, end_line, false, lines)
			vim.api.nvim_buf_set_option(buf, "modifiable", false)
		end
	end

	component.set_title = function(new_title)
		if win and vim.api.nvim_win_is_valid(win) then
			title = new_title
			local config = vim.api.nvim_win_get_config(win)
			config.title = " " .. new_title .. " "
			vim.api.nvim_win_set_config(win, config)
		end
	end

	if opts.mappings then
		utils.set_buffer_mappings(buf, opts.mappings)
	end

	return component
end

return M
