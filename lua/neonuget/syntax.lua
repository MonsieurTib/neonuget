local M = {}

function M.setup()
	vim.cmd([[
    syntax clear
    
    syntax match NeonugetHeader /^#.*/
    syntax match NeonugetSubHeader /^##.*/
    syntax match NeonugetBold /\*\*.\{-}\*\*/
    
    " Package information
    syntax match NeonugetPackageName /^# Package: .\+$/
    syntax match NeonugetVersion /\d\+\.\d\+\.\d\+\(-[a-zA-Z0-9.]\+\)\?/
    
    " Status indicators
    syntax match NeonugetOutdated /This package has an update available!/
    syntax keyword NeonugetSection Top-level Transitive
    
    " Code blocks
    syntax region NeonugetCodeBlock start=/```/ end=/```/
    
    " Command Examples
    syntax match NeonugetCommand /dotnet add package.\+/
    
    " Set highlight groups
    highlight default link NeonugetHeader Title
    highlight default link NeonugetSubHeader Statement
    highlight default link NeonugetBold Special
    highlight default link NeonugetPackageName Title
    highlight default link NeonugetVersion Number
    highlight default link NeonugetOutdated WarningMsg
    highlight default link NeonugetSection Type
    highlight default link NeonugetCodeBlock Comment
    highlight default link NeonugetCommand String
  ]])
end

return M
