# NeoNuGet.nvim

Manage your .NET project's NuGet packages without leaving Neovim! `neonuget.nvim` provides an interactive floating window UI to list installed packages (top-level and transitive), search for available packages on NuGet.org, view package details and versions, and install/uninstall packages using the `dotnet` CLI.

## Features

- **List Packages**: View installed NuGet packages.
- **Search Packages**: Search for available packages on NuGet.org.
- **View Details**: Display metadata (description, author, license, etc.) for selected package versions.
- **View Versions**: List all available versions for a package.
- **Install/Uninstall**: Add or remove packages via the interactive UI (uses `dotnet` CLI).
- **Interactive UI**: Uses floating windows for package lists, search, details, and versions.

## Preview

<img width="2077" alt="neonuget" src="https://github.com/user-attachments/assets/ec293016-11b9-4a4d-a141-a04ac8d7f35e" />


## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "MonsieurTib/neonuget",
  config = function()
    require("neonuget").setup({
      -- Optional configuration
      dotnet_path = "dotnet", -- Path to dotnet CLI
      default_project = nil, -- Auto-detected, or specify path like "./MyProject/MyProject.csproj"
    })
  end,
  dependencies = {
    "nvim-lua/plenary.nvim", 
  }
}
```

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
  "MonsieurTib/neonuget.nvim",
  requires = { "nvim-lua/plenary.nvim" },
  config = function()
    require("neonuget").setup({
      -- Optional configuration
      dotnet_path = "dotnet", -- Path to dotnet CLI
      default_project = nil, -- Auto-detected, or specify path like "./MyProject/MyProject.csproj"
    })
  end
}
```

## Commands

### `:NuGet`

Opens the main interactive UI. Lists installed packages and allows searching, installing, and uninstalling packages.

## Usage

1. Open a .NET project in Neovim.
2. Run `:NuGet` to open the main UI.
3. **Navigate Lists:** Use arrow keys (`j`/`k`) to move up/down in the package lists (Installed/Available/Versions).
4. **Select Package:** Press `<Enter>` on a package (either installed or available) to view its versions and details in the right-hand panes.
5. **Switch Focus:** Use `<Tab>` to cycle focus between the interactive panes (Search, Installed List, Available List, Versions List, Details Pane).
6. **Search:** Focus the search input (top-left) and type to filter installed packages and search available packages simultaneously.
7. **Install Package:** While the Versions list is focused, press `i` to install the currently selected version.
8. **Uninstall Package:** While the Installed Packages list is focused, press `dd` (or configure another key) to uninstall the selected top-level package.
9. **Close:** Press `q` or `<Esc>` in any pane to close the UI.

## Requirements

- Neovim 0.7+ (Requires `plenary.nvim`)
- .NET SDK (with `dotnet` CLI accessible in your path)
- A valid .NET project file (.csproj, .fsproj, or .vbproj) discoverable in the workspace (searches max 2 levels deep by default).
- `plenary.nvim` plugin.

## Limitations

- **Single Project Focus:** Currently, the plugin detects and operates on the first `.csproj`, `.fsproj`, or `.vbproj` file found in the workspace (searching up to 2 levels deep). Support for explicitly selecting projects in multi-project solutions is planned.
- **Public NuGet Only:** Interaction is limited to the public NuGet.org repository. Support for private/custom NuGet feeds is not yet implemented.

## License

MIT License
