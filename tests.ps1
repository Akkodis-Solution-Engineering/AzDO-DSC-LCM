param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("Unit", "Integration")]
    [string]$type = "Unit",

    # Narrows an Integration run to these tags (e.g. 'HostedIntegration', the suites that do not
    # need a Windows host). Defaults to every Integration test.
    [string[]]$Tag = @('Integration'),

    # Leaves these tags out of an Integration run (e.g. 'AzureDevOpsLive', which only runs on the
    # Azure Arc-enabled self-hosted runner).
    [string[]]$ExcludeTag = @()
)
# Import the Test Helper Module
$TestHelper = Import-Module -Name ".\Tests\TestHelpers\CommonTestFunctions.psm1" -PassThru

# Unload the $Global:RepositoryRoot and $Global:TestPaths variables
Remove-Variable -Name RepositoryRoot -Scope Global -ErrorAction SilentlyContinue
Remove-Variable -Name TestPaths -Scope Global -ErrorAction SilentlyContinue

Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)"

# Pester 5 is required. Load it explicitly: autoload can pick Windows' in-box Pester 3.4, which has
# no New-PesterConfiguration. Fall back to the copy Build.ps1 -ResolveDependency saves.
if (-not (Get-Module -Name Pester -ListAvailable | Where-Object { $_.Version -ge [version]'5.0.0' })) {
    $resolvedPester = Get-ChildItem -Path (Join-Path $PSScriptRoot 'output/RequiredModules/Pester') -Filter 'Pester.psd1' -Recurse -ErrorAction SilentlyContinue |
        Sort-Object { [version]$_.Directory.Name } -Descending -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($resolvedPester) {
        Import-Module -Name $resolvedPester.FullName -Force -ErrorAction Stop
    }
}
if (-not (Get-Module -Name Pester | Where-Object { $_.Version -ge [version]'5.0.0' })) {
    Get-Module -Name Pester | Remove-Module -Force
    Import-Module -Name Pester -MinimumVersion 5.0.0 -ErrorAction Stop
}
Write-Host "Pester Version: $((Get-Module -Name Pester).Version)"

$config = New-PesterConfiguration

$config.Run.Path = ".\Tests\PipelineRunner"
$config.Output.CIFormat = "GitHubActions"
$config.CodeCoverage.Path = @( ".\source\Private", ".\source\Public", ".\source\Classes", ".\source\Enum", ".\Pipeline Rules\", ".\Actions\" )
$config.CodeCoverage.OutputFormat = 'CoverageGutters'
$config.CodeCoverage.OutputPath = ".\output\testResults\codeCoverage.xml"
$config.CodeCoverage.OutputEncoding = 'utf8'

if ($type -eq 'Unit') {
    $config.CodeCoverage.Enabled = $true
    $config.Filter = @{
        Tag = 'Unit'
        ExcludeTag = 'Skip', 'Integration'
    }
} else {
    $config.Filter = @{
        Tag = $Tag
        ExcludeTag = @('Skip', 'Unit') + $ExcludeTag
    }
}

# Get the path to the function being tested

if ($type -ne 'Integration') {
    Invoke-Pester -Configuration $config
    return
}

$config.Run.PassThru = $true
$result = Invoke-Pester -Configuration $config

# Integration suites skip themselves when a live dependency (vault, sshd, WinRM, DSC engine, the
# built module) is missing. CI provisions all of them (scripts/Initialize-HostedIntegrationRunner.ps1)
# and sets PIPELINERUNNER_REQUIRE_INTEGRATION_DEPENDENCIES so that a skip fails the run instead of
# silently dropping that coverage.
$failed = $result.FailedCount -gt 0 -or $result.FailedBlocksCount -gt 0 -or $result.FailedContainersCount -gt 0
if ($env:PIPELINERUNNER_REQUIRE_INTEGRATION_DEPENDENCIES -eq 'true' -and $result.SkippedCount -gt 0) {
    Write-Host "::error::$($result.SkippedCount) integration test(s) were skipped, but PIPELINERUNNER_REQUIRE_INTEGRATION_DEPENDENCIES requires every one to run:"
    $result.Skipped | ForEach-Object { Write-Host "  - $($_.ExpandedPath)" }
    $failed = $true
}

if ($failed) { exit 1 }
