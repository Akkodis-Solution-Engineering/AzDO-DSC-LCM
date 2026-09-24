Function Split-RecurivePath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $false)]
        [int]$Times = 1
    )

    1 .. $Times | ForEach-Object {
        $Path = Split-Path -Path $Path -Parent
    }

    $Path
}

function New-MockFilePath {
    param (
        [Parameter(Mandatory = $true)]
        [string]$FileName
    )

    Join-Path (New-MockDirectoryPath) $FileName
    
}

Function New-MockDirectoryPath {
    param ()

    if ($null -eq $TestDrive) {
        $tempPath = Join-Path $env:TEMP 'Pester'
        $TestDrive = Join-Path $env:TEMP $tempPath
    }

    Join-Path $TestDrive 'Temp'

}



Function Get-FunctionPath {
    param(
        [string[]]$FileNames
    )

    # Locate the scriptroot for the module
    if ($Global:RepositoryRoot -eq $null) {
        $Global:RepositoryRoot = Split-RecurivePath $PSScriptRoot -Times 2
    }

    $ScriptRoot = $Global:RepositoryRoot

    if ($null -eq $Global:TestPaths) {
        $Global:TestPaths = Get-ChildItem -LiteralPath $ScriptRoot -Recurse -File -Include *.ps1 | Where-Object {
            ($_.FullName -notlike "*Tests.ps1") -and
            ($_.FullName -notlike '*\output\*') -and
            ($_.FullName -notlike '*\tests\*') -and
            ($_.FullName -notlike '*/output/*') -and
            ($_.FullName -notlike '*/tests/*')
        }
    }

    # Perform a lookup for all BeforeEach FileNames
    $BeforeEachPath = @()
    ForEach ($FileName in $FileNames) {
        $BeforeEachPath += $Global:TestPaths | Where-Object { $_.Name -eq $FileName }
    }

    return $BeforeEachPath

}

Function Get-ModulePath {

    # Locate the scriptroot for the module
    if ($Global:RepositoryRoot -eq $null) {
        $Global:RepositoryRoot = Split-RecurivePath $PSScriptRoot -Times 2
    }

    $SourcesDirectory   = Join-Path $Global:RepositoryRoot 'source'
    $EnumsDirectory     = Join-Path $SourcesDirectory 'Enum'
    $ClassesDirectory   = Join-Path $SourcesDirectory 'Classes'
    $PublicFunctionsDirectory   = Join-Path $SourcesDirectory 'Public'
    $PrivateFunctionsDirectory  = Join-Path $SourcesDirectory 'Private'

    return @{
        EnumsDirectory = $EnumsDirectory
        SourcesDirectory = $SourcesDirectory
        ClassesDirectory = $ClassesDirectory
        PublicFunctionsDirectory = $PublicFunctionsDirectory
        PrivateFunctionsDirectory = $PrivateFunctionsDirectory
    }

}

Function Copy-TestCasesToTempDrive {

    Write-Host "[Copy-TestCasesToTempDrive] Copying Test Cases to Temp Drive"

    $param = @{
        Path = Join-Path $Global:RepositoryRoot '\Tests\PipelineRunner\Intergration\TestCases'
        Destination = $TestDrive
        Recurse = $true
        Force = $true
    }

    Write-Host "[Copy-TestCasesToTempDrive] Copying Test Cases to Temp Drive - $($param.Path) to $($param.Destination)"

    # Create the destination directory
    New-Item -Path $param.Destination -ItemType Directory -Force
    # Copy the test cases to the destination directory
    Copy-Item @param

    Write-Host "[Copy-TestCasesToTempDrive] Test Cases Copied"

}

Function Install-Dependencies {
    param (
        [string]$ModuleName
    )

    # FOR WINDOWS ONLY
    if ($IsWindows -eq $false) {
        throw "This function is only supported on Windows"
    }

    # Resolve the path to the module directory
    $MockDSCResourceModulePath = Join-Path $Global:RepositoryRoot '\Tests\PipelineRunner\Intergration\Resources\Modules\AzureDevOpsDsc'
    $MockDSCSupportingResourceModulePath = Join-Path $Global:RepositoryRoot '\Tests\PipelineRunner\Intergration\Resources\Modules\AzureDevOpsDsc.Common'
    $PipelineRunnerModulePath = Join-Path $Global:RepositoryRoot '\output\DSC.PipelineRunner.Akkodis'

    # Find the user's module directory
    $ModuleDirectory = $env:PSModulePath.Split(';') | Where-Object { $_ -like "*$ENV:Username*" -and $_ -like "*documents*" }

    # Install the Dependencies
    Install-Module -Name 'PSDesiredStateConfiguration', 'Datum', 'Datum.InvokeCommand' -ErrorAction Stop -Scope CurrentUser

    # Delete the module from the user's module directory
    Remove-Item -Path (Join-Path $ModuleDirectory -ChildPath 'AzureDevOpsDsc') -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $ModuleDirectory -ChildPath 'DSC.PipelineRunner.Akkodis') -Recurse -Force -ErrorAction SilentlyContinue

    # Copy the module into the user's module directory
    Copy-Item -Path $MockDSCResourceModulePath -Destination $ModuleDirectory -Force -Recurse
    Copy-Item -Path $MockDSCSupportingResourceModulePath -Destination $ModuleDirectory -Force -Recurse
    Copy-Item -Path $PipelineRunnerModulePath -Destination $ModuleDirectory -Force -Recurse

    # Import the MockDSCModule
    Import-Module AzureDevOpsDsc -Version 0.0.1 -ErrorAction Stop

    Write-Host "[Install-Dependencies] Dependencies Installed"

}

Function Find-Functions {
    param(
        [String]$TestFilePath
    )

    $files = @()

    #
    # Using the File path of the test file, work out the function that is being tested
    $FunctionName = (Get-Item -LiteralPath $TestFilePath).BaseName -replace '\.tests$', ''
    $files += "$($FunctionName).ps1"


    #
    # Load the function into the AST and look for the mock commands.

    # Parse the PowerShell script file
    $AST = [System.Management.Automation.Language.Parser]::ParseFile($TestFilePath, [ref]$null, [ref]$null)

    # Find all the Mock commands
    $MockCommands = $AST.FindAll({
        $args[0] -is [System.Management.Automation.Language.CommandAst] -and
        $args[0].CommandElements[0].Value -eq 'Mock'
    }, $true)

    # Iterate over the Mock commands and find the CommandName parameter
    foreach ($mockCommand in $MockCommands) {

        # Iterate over the CommandElements
        foreach ($element in $mockCommand.CommandElements) {

            # Check if the element is a CommandParameterAst and the parameter name is CommandName
            if ($element -is [System.Management.Automation.Language.CommandParameterAst] -and $element.ParameterName -eq 'CommandName') {
                $null = $element.Parent.Extent.Text -match '(-CommandName\s+(?<Function>[^\s]+))|(^Mock (?<Function>[^\s]+$))'
                $files += "$($matches.Function).ps1"
            }
        }
    }

    # Ignore the following list of functions
    $files = $files | Where-Object { $_ -notin @('Write-Error.ps1', 'Write-Output.ps1', 'Write-Verbose.ps1', 'Write-Warning.ps1') }
    # Return the unique list of functions
    $files = $files | Select-Object -Unique

    $files

}

Function Get-ClassFilePath {
    param(
        [string]$FileName
    )

    $Class = $Global:TestPaths | Where-Object { ($_.Name -eq $FileName) -or ($_.Name -eq "$FileName.ps1") }
    return $Class.FullName

}

Function Import-Enums {
    return ($Global:TestPaths | Where-Object { $_.Directory.Name -eq 'Enum' })
}

<#
.SYNOPSIS
Returns why the live WinRM integration suite cannot run here, or $null when it can.

.DESCRIPTION
Lives in this module, rather than inline in the test file, because Pester runs discovery and
execution in separate scopes: a variable assigned at a test file's top level is visible when
Pester evaluates an It's -Skip: argument (discovery) but NOT inside BeforeAll (execution). The
probe therefore has to be callable from both, which a module command is and a file-scope
variable is not.

It probes TWICE, and the second probe is the one that matters. A bare Test-WSMan sends an
ANONYMOUS WS-Man Identify: it answers as soon as a listener exists, without authenticating
anybody. The suite does not open anonymous connections - New-CimSession and New-PSSession
authenticate as the current user - so a host can pass a bare Test-WSMan and still refuse every
session the suite opens ("Access is denied"), which is a skip condition reported as four
failures. Adding -Authentication Negotiate makes the Identify go through the same
authentication the suite's own sessions use, so what this returns matches what the tests will
actually get. Keeping both probes is what lets the reason distinguish "no listener here" from
"a listener that will not authenticate this account".

scripts/Enable-SelfHostedWinRM.ps1 probes the same way, for the same reason: an anonymous
probe would let it declare a host already configured when the suite cannot use it.
#>
function Get-WinRMSkipReason {
    [CmdletBinding()]
    param(
        [string]$ComputerName = $env:COMPUTERNAME
    )

    if (-not $IsWindows) {
        return 'Target/WinRM requires a Windows host with a WinRM listener; this is not Windows.'
    }

    try {
        $null = Test-WSMan -ComputerName $ComputerName -ErrorAction Stop
    }
    catch {
        return "Test-WSMan against [$ComputerName] failed: $($_.Exception.Message)"
    }

    try {
        $null = Test-WSMan -ComputerName $ComputerName -Authentication Negotiate -ErrorAction Stop
    }
    catch {
        return "A WinRM listener on [$ComputerName] answered an anonymous Test-WSMan, but an authenticated one failed: $($_.Exception.Message)"
    }

    return $null
}

<#
.SYNOPSIS
Returns why the live SecretManagement vault integration suite cannot run here, or $null when it
can.

.DESCRIPTION
See Get-WinRMSkipReason for why this is a module command rather than a variable in the test file.

Two conditions. Both SecretManagement and the SecretStore extension must be installed, and
PIPELINERUNNER_ALLOW_SECRETSTORE_RESET must be 'true': configuring SecretStore for unattended
use means Reset-SecretStore, which erases the CURRENT USER's secrets. That is harmless on an
ephemeral CI agent and destructive on a developer's machine, so it never happens by default.
#>
function Get-LiveVaultSkipReason {
    [CmdletBinding()]
    param()

    if (-not (Get-Module -ListAvailable -Name Microsoft.PowerShell.SecretManagement)) {
        return 'Microsoft.PowerShell.SecretManagement is not installed.'
    }

    if (-not (Get-Module -ListAvailable -Name Microsoft.PowerShell.SecretStore)) {
        return 'Microsoft.PowerShell.SecretStore (the vault extension used by this suite) is not installed.'
    }

    if ($env:PIPELINERUNNER_ALLOW_SECRETSTORE_RESET -ne 'true') {
        return 'PIPELINERUNNER_ALLOW_SECRETSTORE_RESET is not set to "true"; refusing to reset this user''s SecretStore.'
    }

    return $null
}

<#
.SYNOPSIS
Returns why the live SSH remoting integration suite cannot run here, or $null when it can.

.DESCRIPTION
See Get-WinRMSkipReason for why this is a module command rather than a variable in the test file
(Pester evaluates -Skip: during discovery and BeforeAll during execution - separate scopes).

Three conditions, probed in the order they fail in practice:

  1. PowerShell's SSH remoting has no transport of its own - it shells out to the platform ssh
     client - so without an 'ssh' on PATH nothing else is worth trying.
  2. The client must be able to authenticate to the target NON-INTERACTIVELY. BatchMode=yes is
     what makes that a failure rather than a password prompt that hangs a CI job forever, and
     host-key checking is deliberately left at its default: a suite that silently accepted an
     unknown host key would be proving less than it appears to.
  3. sshd on the target must have a 'powershell' subsystem registered. That is a line in
     sshd_config, not something the ssh client can report, so the only honest probe is to open
     a real session and close it again - the SSH analogue of Get-WinRMSkipReason's authenticated
     Test-WSMan. Without it the connection succeeds and the subsystem request is refused, which
     would otherwise surface as every test failing rather than the suite skipping.

.PARAMETER ComputerName
The SSH target. Defaults to PIPELINERUNNER_SSH_TARGET, then 'localhost' - the loopback form the
hosted integration workflow sets up, where the agent SSHes to itself.
#>
function Get-SshRemotingSkipReason {
    [CmdletBinding()]
    param(
        [string]$ComputerName
    )

    if ([string]::IsNullOrWhiteSpace($ComputerName)) {
        $ComputerName = $env:PIPELINERUNNER_SSH_TARGET
    }
    if ([string]::IsNullOrWhiteSpace($ComputerName)) {
        $ComputerName = 'localhost'
    }

    if (-not (Get-Command -Name ssh -CommandType Application -ErrorAction SilentlyContinue)) {
        return 'No ssh client is on PATH; PowerShell SSH remoting shells out to one.'
    }

    $probeOutput = & ssh -o BatchMode=yes -o ConnectTimeout=10 $ComputerName 'exit 0' 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        return "ssh could not authenticate to [$ComputerName] non-interactively (exit $LASTEXITCODE): $($probeOutput.Trim())"
    }

    try {
        $probeSession = New-PSSession -HostName $ComputerName -SSHTransport -ErrorAction Stop
        Remove-PSSession -Session $probeSession -ErrorAction SilentlyContinue
    }
    catch {
        return "ssh reaches [$ComputerName], but no PowerShell remoting session could be opened over it (is the 'powershell' subsystem registered in sshd_config?): $($_.Exception.Message)"
    }

    return $null
}

<#
.SYNOPSIS
Captures the process environment so a suite can put it back in AfterAll.

.DESCRIPTION
Every Pester file in a run shares one process. A suite that drives a real runner pass leaks
into that process environment: Set-Variables publishes each configuration variable as an env
var (a variable named 'ProjectName' becomes $env:ProjectName), and some suites prepend fixture
paths to PSModulePath. The files that run later inherit that state. Invoke-DscPipelineRunner.tests.ps1
calls Build.ps1, which reads 'property ProjectName' from the environment, so a leaked value
makes it build a module that does not exist and its BeforeAll fails.
#>
function Save-ProcessEnvironment {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $snapshot = @{}
    foreach ($entry in [System.Environment]::GetEnvironmentVariables([System.EnvironmentVariableTarget]::Process).GetEnumerator()) {
        $snapshot[[string]$entry.Key] = [string]$entry.Value
    }
    return $snapshot
}

<#
.SYNOPSIS
Restores the process environment captured by Save-ProcessEnvironment. It removes variables
that were added since the snapshot and resets variables that changed.
#>
function Restore-ProcessEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [hashtable]$Snapshot
    )

    # BeforeAll may have thrown before the snapshot was taken; leave the environment alone then.
    if ($null -eq $Snapshot) { return }

    $current = [System.Environment]::GetEnvironmentVariables([System.EnvironmentVariableTarget]::Process)
    foreach ($name in @($current.Keys)) {
        if (-not $Snapshot.ContainsKey([string]$name)) {
            [System.Environment]::SetEnvironmentVariable([string]$name, $null, [System.EnvironmentVariableTarget]::Process)
        }
    }
    foreach ($name in $Snapshot.Keys) {
        if ($current[$name] -ne $Snapshot[$name]) {
            [System.Environment]::SetEnvironmentVariable($name, $Snapshot[$name], [System.EnvironmentVariableTarget]::Process)
        }
    }
}

Export-ModuleMember -Function Split-RecurivePath, Get-FunctionPath, Find-Functions, Get-ClassFilePath, Import-Enums, New-MockDirectoryPath, New-MockFilePath, Install-Dependencies, Copy-TestCasesToTempDrive, Get-ModulePath, Get-WinRMSkipReason, Get-LiveVaultSkipReason, Get-SshRemotingSkipReason, Save-ProcessEnvironment, Restore-ProcessEnvironment
