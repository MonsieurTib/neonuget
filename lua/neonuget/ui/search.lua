local M = {}

local utils = require("neonuget.ui.utils")
local baseui = require("neonuget.ui.baseui")

function M.create(opts)
	opts = opts or {}
	local width = opts.width or 30
	local height = 1
	local col = opts.col or 0
	local row = opts.row or 0
	local on_change = opts.on_change or function() end

	local component = baseui.create_component({
		title = "Search",
		width = width,
		height = height,
		col = col,
		row = row,
		buffer_name = "NuGet_Search",
		initial_content = { "" },
		focus = false,
		cursorline = false,
		number = false,
		relativenumber = false,
		mappings = {
			i = {
				["<Tab>"] = function()
					vim.cmd("stopinsert")
					if opts.on_tab then
						opts.on_tab()
					end
				end,
				["<Esc>"] = function()
					vim.cmd("stopinsert")
					if opts.on_escape then
						opts.on_escape()
					end
				end,
				["<CR>"] = function()
					vim.cmd("stopinsert")
					if opts.on_enter then
						opts.on_enter()
					end
				end,
			},
			n = {
				["<Tab>"] = function()
					if opts.on_tab then
						opts.on_tab()
					end
				end,
				["q"] = function()
					if opts.on_close then
						opts.on_close()
					end
				end,
				["<Esc>"] = function()
					if opts.on_escape then
						opts.on_escape()
					end
				end,
				["i"] = function()
					component.activate()
				end,
			},
		},
	})

	if not component then
		return nil
	end

	local search_timer = nil
	local last_search_term = nil

	local function start_search_updates()
		if search_timer then
			search_timer:stop()
		end
		search_timer = vim.loop.new_timer()
		search_timer:start(
			0,
			150,
			vim.schedule_wrap(function()
				if not component.win or not vim.api.nvim_win_is_valid(component.win) then
					return
				end

				local mode = vim.api.nvim_get_mode().mode
				if mode ~= "i" then
					return
				end

				local current_line = vim.api.nvim_buf_get_lines(component.buf, 0, 1, false)[1] or ""

				if current_line ~= last_search_term then
					on_change(current_line)
					last_search_term = current_line
				end
			end)
		)
	end

	local function stop_search_updates()
		if search_timer then
			search_timer:stop()
			search_timer:close()
			search_timer = nil
		end
		last_search_term = nil
	end

	component.activate = function()
		if not component.win or not vim.api.nvim_win_is_valid(component.win) then
			return
		end

		vim.api.nvim_set_current_win(component.win)
		vim.api.nvim_buf_set_option(component.buf, "modifiable", true)
		vim.cmd("startinsert")

		utils.configure_window(component.win, {
			number = false,
			relativenumber = false,
		})

		utils.set_focused_border_color(component.win, true)

		vim.cmd("redraw")
	end

	local original_close = component.close
	component.close = function()
		stop_search_updates()
		original_close()
	end

	component.start_updates = start_search_updates
	component.stop_updates = stop_search_updates

	local augroup = vim.api.nvim_create_augroup("NuGetSearchTimer_" .. component.buf, { clear = true })
	vim.api.nvim_create_autocmd("InsertEnter", {
		group = augroup,
		buffer = component.buf,
		callback = start_search_updates,
	})
	vim.api.nvim_create_autocmd("InsertLeave", {
		group = augroup,
		buffer = component.buf,
		callback = stop_search_updates,
	})

	return component
end

return M
