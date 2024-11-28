# Import the Test Helper Module
$TestHelper = Import-Module -Name ".\Tests\TestHelpers\CommonTestFunctions.psm1" -PassThru

# Unload the $Global:RepositoryRoot and $Global:TestPaths variables
Remove-Variable -Name RepositoryRoot -Scope Global -ErrorAction SilentlyContinue
Remove-Variable -Name TestPaths -Scope Global -ErrorAction SilentlyContinue

Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)"

$config = New-PesterConfiguration

$config.Run.Path = ".\Tests\LCM"
$config.Output.CIFormat = "GitHubActions"
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = @( ".\source\Private", ".\source\Public", ".\LCM Rules\" )
$config.CodeCoverage.OutputFormat = 'CoverageGutters'
$config.CodeCoverage.OutputPath = ".\output\testResults\codeCoverage.xml"
$config.CodeCoverage.OutputEncoding = 'utf8'
$config.Filter = @{
    ExcludeTag = 'Skip', 'Integration'
}

# Get the path to the function being tested

Invoke-Pester -Configuration $config
