local M = {}

local curl
local curl_ok, _ = pcall(require, "plenary.curl")
if curl_ok then
	curl = require("plenary.curl")
else
	vim.notify("plenary.curl is not available. Please install plenary.nvim.", vim.log.levels.ERROR)
end

local NUGET_API_BASE_URL = "https://api.nuget.org/v3-flatcontainer/"
local NUGET_REGISTRATION_BASE_URL = "https://api.nuget.org/v3/registration5-semver1/"
local NUGET_SEARCH_BASE_URL = "https://azuresearch-usnc.nuget.org/query"

local function make_request(url, callback, error_message)
	if not curl then
		callback(nil, "curl is not available")
		return
	end

	error_message = error_message or "Failed to fetch data from NuGet API"

	curl.get(url, {
		callback = vim.schedule_wrap(function(response)
			if not response or response.exit ~= 0 or not response.body or response.body == "" then
				local details = ""
				if response then
					details = "Exit code: " .. tostring(response.exit)
					if response.stderr and response.stderr ~= "" then
						details = details .. " - " .. response.stderr
					end
				end

				print("[ERROR] " .. error_message .. " - Details: " .. details)
				callback(nil, error_message)
				return
			end
			callback(response.body, nil)
		end),
	})
end

function M.fetch_package_versions(package_id, callback)
	if not package_id or package_id == "" then
		vim.notify("Invalid package ID provided", vim.log.levels.ERROR)
		callback(nil)
		return
	end

	local url = NUGET_API_BASE_URL .. string.lower(package_id) .. "/index.json"
	make_request(url, function(body, err)
		if err then
			vim.notify("Could not fetch package information", vim.log.levels.ERROR)
			callback(nil)
			return
		end

		local ok, parsed_info = pcall(M.parse_package_info, body)

		if not ok or not parsed_info then
			vim.notify("Failed to parse package info", vim.log.levels.ERROR)
			callback(nil)
			return
		end

		callback(parsed_info)
	end, "Failed to fetch package versions for " .. package_id)
end

function M.parse_package_info(json_str)
	if not json_str or json_str == "" then
		return nil
	end

	local ok, json_data = pcall(vim.fn.json_decode, json_str)

	if not ok or not json_data or not json_data.versions then
		return nil
	end

	return json_data.versions
end

function M.fetch_package_metadata(package_id, version, callback)
	if not package_id or package_id == "" then
		vim.notify("Invalid package ID provided for metadata fetch", vim.log.levels.ERROR)
		callback(nil)
		return
	end
	if not version or version == "" then
		vim.notify("Invalid version provided for metadata fetch", vim.log.levels.ERROR)
		callback(nil)
		return
	end

	local base_url = NUGET_REGISTRATION_BASE_URL
	local url = base_url .. string.lower(package_id) .. "/" .. version .. ".json"

	make_request(url, function(body, err)
		if err then
			vim.notify("Could not fetch package metadata", vim.log.levels.ERROR)
			callback(nil)
			return
		end

		local ok, result = pcall(M.parse_package_metadata, body)

		if not ok then
			vim.notify("Error during metadata parsing", vim.log.levels.ERROR)
			callback(nil)
			return
		end

		if type(result) == "string" then
			vim.notify("Failed to parse package metadata", vim.log.levels.ERROR)
			callback(nil)
			return
		end

		if result and result._needs_catalog_fetch and result.url then
			if result.id then
				package_id = result.id
			end

			M.fetch_catalog_metadata(result.url, callback)
			return
		end

		callback(result)
	end, "Failed to fetch metadata for " .. package_id .. " version " .. version)
end

function M.process_tags(tags)
	if not tags then
		return {}
	end

	if type(tags) == "table" then
		return tags
	end

	if type(tags) == "string" and tags ~= "" then
		local result = {}
		for tag in string.gmatch(tags, "([^,%s;]+)") do
			table.insert(result, tag)
		end
		return result
	end

	return {}
end

function M.fetch_catalog_metadata(catalog_url, callback)
	if not catalog_url or catalog_url == "" then
		vim.notify("Invalid catalog URL provided", vim.log.levels.ERROR)
		callback(nil)
		return
	end
	make_request(catalog_url, function(body, err)
		if err then
			vim.notify("Could not fetch catalog metadata", vim.log.levels.ERROR)
			callback(nil)
			return
		end

		local ok, json_data = pcall(vim.fn.json_decode, body)

		if not ok then
			vim.notify("Failed to parse catalog JSON", vim.log.levels.ERROR)
			callback(nil)
			return
		end

		local catalog_data = json_data

		if json_data.catalogEntry then
			if type(json_data.catalogEntry) == "table" then
				catalog_data = json_data.catalogEntry
			end
		end

		local metadata = {
			description = catalog_data.description or "",
			authors = catalog_data.authors or "",
			published = catalog_data.published or "",
			totalDownloads = catalog_data.totalDownloads or json_data.totalDownloads or 0,
			tags = M.process_tags(catalog_data.tags),
			projectUrl = catalog_data.projectUrl or "",
			licenseUrl = catalog_data.licenseUrl or "",
		}

		callback(metadata)
	end, "Failed to fetch catalog metadata from " .. catalog_url)
end

function M.parse_package_metadata(json_str)
	if not json_str or json_str == "" then
		return "Empty JSON string received"
	end

	local ok, json_data = pcall(vim.fn.json_decode, json_str)

	if not ok then
		return "JSON decode failed: " .. tostring(json_data)
	end

	local catalog_entry
	local catalog_url
	local package_id = nil
	local download_count = nil

	if json_data.id then
		package_id = json_data.id
	end

	if json_data.totalDownloads then
		download_count = json_data.totalDownloads
	end

	if json_data.catalogEntry then
		if type(json_data.catalogEntry) == "string" then
			catalog_url = json_data.catalogEntry
		else
			catalog_entry = json_data.catalogEntry
			if catalog_entry.id and not package_id then
				package_id = catalog_entry.id
			end

			if catalog_entry.totalDownloads and not download_count then
				download_count = catalog_entry.totalDownloads
			end
		end
	elseif json_data.items and #json_data.items > 0 then
		local latest_page = json_data.items[#json_data.items]

		if latest_page and latest_page.items and #latest_page.items > 0 then
			local latest_item = latest_page.items[#latest_page.items]

			if latest_item.id and not package_id then
				package_id = latest_item.id
			end

			if latest_item.totalDownloads and not download_count then
				download_count = latest_item.totalDownloads
			end

			if latest_item and latest_item.catalogEntry then
				if type(latest_item.catalogEntry) == "string" then
					catalog_url = latest_item.catalogEntry
				else
					catalog_entry = latest_item.catalogEntry
					if catalog_entry.id and not package_id then
						package_id = catalog_entry.id
					end

					if catalog_entry.totalDownloads and not download_count then
						download_count = catalog_entry.totalDownloads
					end
				end
			end
		end
	end

	if catalog_url then
		return { _needs_catalog_fetch = true, url = catalog_url, id = package_id, totalDownloads = download_count }
	end

	if not catalog_entry then
		if json_data.data and #json_data.data > 0 then
			local latest_item = json_data.data[1]
			catalog_entry = latest_item
			if latest_item.id and not package_id then
				package_id = latest_item.id
			end

			if latest_item.totalDownloads and not download_count then
				download_count = latest_item.totalDownloads
			end
		elseif json_data.description then
			catalog_entry = json_data
			if json_data.totalDownloads and not download_count then
				download_count = json_data.totalDownloads
			end
		else
			return "Could not find catalog entry in JSON structure: " .. vim.inspect(vim.tbl_keys(json_data))
		end
	end

	local metadata = {
		description = catalog_entry.description or "",
		authors = catalog_entry.authors or "",
		published = catalog_entry.published or "",
		totalDownloads = download_count or catalog_entry.totalDownloads or 0,
		tags = M.process_tags(catalog_entry.tags),
		projectUrl = catalog_entry.projectUrl or "",
		licenseUrl = catalog_entry.licenseUrl or "",
	}

	return metadata
end

function M.parse_json_package_list(json_str)
	local packages = {}

	if not json_str or json_str == "" then
		vim.notify("Empty JSON data received", vim.log.levels.ERROR)
		return packages
	end

	local ok, json_data
	ok, json_data = pcall(vim.fn.json_decode, json_str)

	if not ok or not json_data then
		vim.notify("Failed to parse JSON: " .. (json_data or "unknown error"), vim.log.levels.ERROR)
		return packages
	end

	if not json_data.projects then
		vim.notify("No projects found in JSON data", vim.log.levels.WARN)
		return packages
	end

	for _, project in ipairs(json_data.projects) do
		if project.frameworks then
			for _, framework in ipairs(project.frameworks) do
				if framework.topLevelPackages then
					for _, pkg in ipairs(framework.topLevelPackages) do
						table.insert(packages, {
							section = "Top-level",
							name = pkg.id,
							is_top_level = true,
							requested_version = pkg.requestedVersion or "",
							resolved_version = pkg.resolvedVersion or "",
							latest_version = pkg.latestVersion or "",
						})
					end
				end

				if framework.transitivePackages then
					for _, pkg in ipairs(framework.transitivePackages) do
						table.insert(packages, {
							section = "Transitive",
							name = pkg.id,
							is_top_level = false,
							requested_version = pkg.requestedVersion or "",
							resolved_version = pkg.resolvedVersion or "",
							latest_version = pkg.latestVersion or "",
						})
					end
				end
			end
		end
	end

	return packages
end

function M.fetch_available_packages(params, callback)
	params = params or {}
	local q = params.q or ""
	local prerelease = params.prerelease or false
	local semVerLevel = params.semVerLevel or "2.0.0"
	local take = params.take or 10
	local skip = params.skip or 0
	local sortBy = params.sortBy or "relevance"

	local base_url = NUGET_SEARCH_BASE_URL
	local query_string = "?q="
		.. vim.uri_encode(q)
		.. "&prerelease="
		.. tostring(prerelease)
		.. "&semVerLevel="
		.. semVerLevel
		.. "&take="
		.. tostring(take)
		.. "&skip="
		.. tostring(skip)
		.. "&sortBy="
		.. sortBy

	local full_url = base_url .. query_string

	make_request(full_url, function(body, err)
		if err then
			vim.notify("Could not fetch available packages", vim.log.levels.ERROR)
			callback(nil)
			return
		end

		local ok, parsed_data = pcall(M.parse_available_packages, body)

		if not ok or not parsed_data then
			vim.notify("Failed to parse available packages", vim.log.levels.ERROR)
			callback(nil)
			return
		end

		callback(parsed_data)
	end, "Failed to fetch available packages with query '" .. q .. "'")
end

function M.parse_available_packages(json_str)
	if not json_str or json_str == "" then
		return nil
	end

	local ok, json_data = pcall(vim.fn.json_decode, json_str)

	if not ok or not json_data then
		return nil
	end

	local packages = {}
	local total_count = json_data.totalHits or 0

	if json_data.data and #json_data.data > 0 then
		for _, pkg in ipairs(json_data.data) do
			table.insert(packages, {
				section = "Available",
				name = pkg.id,
				is_top_level = false,
				resolved_version = pkg.version or "",
				latest_version = pkg.version or "",
				description = pkg.description or "",
				authors = pkg.authors or "",
				total_downloads = pkg.totalDownloads or 0,
				icon_url = pkg.iconUrl or "",
			})
		end
	end

	return {
		packages = packages,
		total_count = total_count,
	}
end

return M
