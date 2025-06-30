local M = {}

local curl
local curl_ok, _ = pcall(require, "plenary.curl")
if curl_ok then
  curl = require("plenary.curl")
else
  vim.notify("plenary.curl is not available. Please install plenary.nvim.", vim.log.levels.ERROR)
end

local NUGET_API_BASE_URL = "https://api.nuget.org/v3-flatcontainer/"
local NUGET_REGISTRATION_BASE_URL = "https://api.nuget.org/v3/registration5-gz-semver2/"
local NUGET_SEARCH_BASE_URL = "https://azuresearch-usnc.nuget.org/query"

local function make_request(url, callback, error_message, use_compression)
  if not curl then
    callback(nil, "curl is not available")
    return
  end

  error_message = error_message or "Failed to fetch data from NuGet API"
  use_compression = use_compression or false

  local request_options = {
    headers = {
      ["Accept"] = "application/json",
    },
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
  }

  if use_compression then
    request_options.headers["Accept-Encoding"] = "gzip, deflate"
    request_options.compressed = true
  end

  curl.get(url, request_options)
end

function M.fetch_package_versions(package_id, callback)
  if not package_id or package_id == "" then
    vim.notify("Invalid package ID provided", vim.log.levels.ERROR)
    callback(nil)
    return
  end

  local url = NUGET_REGISTRATION_BASE_URL .. string.lower(package_id) .. "/index.json"
  make_request(url, function(body, err)
    if err then
      vim.notify("Could not fetch package information: " .. err, vim.log.levels.ERROR)
      callback(nil)
      return
    end

    local ok, parsed_info = pcall(vim.fn.json_decode, body)

    if not ok or not parsed_info then
      vim.notify("Failed to parse package info JSON", vim.log.levels.ERROR)
      callback(nil)
      return
    end

    if parsed_info and parsed_info.items and #parsed_info.items > 0 then
      local versions = {}
      local version_pages = parsed_info.items

      local has_nested_items = false
      for _, page in ipairs(version_pages) do
        if page.items and #page.items > 0 then
          has_nested_items = true
          for _, item in ipairs(page.items) do
            if item.catalogEntry and item.catalogEntry.version then
              table.insert(versions, item.catalogEntry.version)
            end
          end
        else
          table.insert(versions, {
            lower = page.lower,
            upper = page.upper,
            page_url = page["@id"],
          })
        end
      end

      if has_nested_items then
        callback(versions)
      else
        M.fetch_version_pages(versions, callback)
      end
    else
      local fallback_url = NUGET_API_BASE_URL .. string.lower(package_id) .. "/index.json"
      make_request(fallback_url, function(fallback_body, fallback_err)
        if fallback_err then
          vim.notify("Could not fetch package information using fallback", vim.log.levels.ERROR)
          callback(nil)
          return
        end

        local fallback_ok, fallback_data = pcall(M.parse_package_info, fallback_body)
        if not fallback_ok or not fallback_data then
          vim.notify("Failed to parse package info with fallback method", vim.log.levels.ERROR)
          callback(nil)
          return
        end

        callback(fallback_data)
      end, false)
    end
  end, "Failed to fetch package versions for " .. package_id, true)
end

function M.fetch_all_package_versions(package_id, callback)
  if not package_id or package_id == "" then
    vim.notify("Invalid package ID provided", vim.log.levels.ERROR)
    callback(nil)
    return
  end

  local url = NUGET_REGISTRATION_BASE_URL .. string.lower(package_id) .. "/index.json"
  make_request(url, function(body, err)
    if err then
      vim.notify("Could not fetch package information: " .. err, vim.log.levels.ERROR)
      callback(nil)
      return
    end

    local ok, parsed_info = pcall(vim.fn.json_decode, body)

    if not ok or not parsed_info then
      vim.notify("Failed to parse package info JSON", vim.log.levels.ERROR)
      callback(nil)
      return
    end

    if parsed_info and parsed_info.items and #parsed_info.items > 0 then
      local version_infos = {}
      local version_pages = parsed_info.items

      local has_nested_items = false
      for _, page in ipairs(version_pages) do
        if page.items and #page.items > 0 then
          has_nested_items = true
          for _, item in ipairs(page.items) do
            if item.catalogEntry then
              local catalog_entry = item.catalogEntry
              local version_info = {
                version = catalog_entry.version or "",
                description = catalog_entry.description or "",
                authors = catalog_entry.authors or "",
                published = catalog_entry.published or "",
                totalDownloads = catalog_entry.totalDownloads or 0,
                tags = M.process_tags(catalog_entry.tags),
                projectUrl = catalog_entry.projectUrl or "",
                licenseUrl = catalog_entry.licenseUrl or "",
                dependencies = catalog_entry.dependencyGroups or {},
              }
              table.insert(version_infos, version_info)
            end
          end
        end
      end

      if has_nested_items then
        callback(version_infos)
      else
        local pages_to_fetch = {}
        for _, page in ipairs(version_pages) do
          if page["@id"] then
            table.insert(pages_to_fetch, {
              url = page["@id"],
              lower = page.lower,
              upper = page.upper,
            })
          end
        end

        if #pages_to_fetch > 0 then
          M.fetch_version_pages_with_metadata(pages_to_fetch, callback)
        else
          M.fallback_fetch_versions(package_id, callback)
        end
      end
    else
      M.fallback_fetch_versions(package_id, callback)
    end
  end, "Failed to fetch package versions for " .. package_id, true)
end

function M.fallback_fetch_versions(package_id, callback)
  local fallback_url = NUGET_API_BASE_URL .. string.lower(package_id) .. "/index.json"
  make_request(fallback_url, function(fallback_body, fallback_err)
    if fallback_err then
      vim.notify("Could not fetch package information using fallback", vim.log.levels.ERROR)
      callback(nil)
      return
    end

    local fallback_ok, versions = pcall(M.parse_package_info, fallback_body)
    if not fallback_ok or not versions then
      vim.notify("Failed to parse package info with fallback method", vim.log.levels.ERROR)
      callback(nil)
      return
    end

    local version_infos = {}
    for _, version_str in ipairs(versions) do
      table.insert(version_infos, {
        version = version_str,
        description = "No description available",
        authors = "Unknown",
        published = "",
        totalDownloads = 0,
        tags = {},
        projectUrl = "",
        licenseUrl = "",
      })
    end

    callback(version_infos)
  end, false)
end

function M.fetch_version_pages_with_metadata(version_pages, callback)
  if not version_pages or #version_pages == 0 then
    callback({})
    return
  end

  local version_infos = {}
  local pending_requests = #version_pages

  for _, page in ipairs(version_pages) do
    make_request(page.url, function(body, err)
      pending_requests = pending_requests - 1

      if not err and body then
        local ok, page_data = pcall(vim.fn.json_decode, body)
        if ok and page_data then
          if page_data.items and #page_data.items > 0 then
            for _, item in ipairs(page_data.items) do
              if item.catalogEntry then
                local catalog_entry = item.catalogEntry
                local version_info = {
                  version = catalog_entry.version or "",
                  description = catalog_entry.description or "",
                  authors = catalog_entry.authors or "",
                  published = catalog_entry.published or "",
                  totalDownloads = catalog_entry.totalDownloads or 0,
                  tags = M.process_tags(catalog_entry.tags),
                  projectUrl = catalog_entry.projectUrl or "",
                  licenseUrl = catalog_entry.licenseUrl or "",
                  dependencies = catalog_entry.dependencyGroups or {},
                }
                table.insert(version_infos, version_info)
              elseif item.version or item["@id"] then
                local version_info = {
                  version = item.version or "",
                  description = item.description or "",
                  authors = item.authors or "",
                  published = item.published or "",
                  totalDownloads = item.totalDownloads or 0,
                  tags = M.process_tags(item.tags),
                  projectUrl = item.projectUrl or "",
                  licenseUrl = item.licenseUrl or "",
                }
                table.insert(version_infos, version_info)
              end
            end
          elseif page_data.version then
            local version_info = {
              version = page_data.version or "",
              description = page_data.description or "",
              authors = page_data.authors or "",
              published = page_data.published or "",
              totalDownloads = page_data.totalDownloads or 0,
              tags = M.process_tags(page_data.tags),
              projectUrl = page_data.projectUrl or "",
              licenseUrl = page_data.licenseUrl or "",
            }
            table.insert(version_infos, version_info)
          end
        end
      end

      if pending_requests == 0 then
        table.sort(version_infos, function(a, b)
          return a.version > b.version
        end)

        local unique_versions = {}
        local seen = {}
        for _, v in ipairs(version_infos) do
          if v.version and v.version ~= "" and not seen[v.version] then
            seen[v.version] = true
            table.insert(unique_versions, v)
          end
        end

        callback(unique_versions)
      end
    end, "Failed to fetch version page: " .. page.url, true)
  end
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
  end, "Failed to fetch metadata for " .. package_id .. " version " .. version, true)
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
  end, "Failed to fetch catalog metadata from " .. catalog_url, true)
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
  end, "Failed to fetch available packages with query '" .. q .. "'", false)
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
