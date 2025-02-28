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

    $SourcesDirectory = Join-Path $Global:RepositoryRoot 'source'
    $ClassesDirectory = Join-Path $SourcesDirectory 'Classes'
    $PublicFunctionsDirectory = Join-Path $SourcesDirectory 'Public'
    $PrivateFunctionsDirectory = Join-Path $SourcesDirectory 'Private'

    return @{
        SourcesDirectory = $SourcesDirectory
        ClassesDirectory = $ClassesDirectory
        PublicFunctionsDirectory = $PublicFunctionsDirectory
        PrivateFunctionsDirectory = $PrivateFunctionsDirectory
    }

}

Function Copy-TestCasesToTempDrive {

    Write-Host "[Copy-TestCasesToTempDrive] Copying Test Cases to Temp Drive"

    $param = @{
        Path = Join-Path $Global:RepositoryRoot '\Tests\LCM\Intergration\TestCases'
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
    $MockDSCResourceModulePath = Join-Path $Global:RepositoryRoot '\Tests\LCM\Intergration\Resources\Modules\AzureDevOpsDsc'
    $MockDSCSupportingResourceModulePath = Join-Path $Global:RepositoryRoot '\Tests\LCM\Intergration\Resources\Modules\AzureDevOpsDsc.Common'
    $LCMModulePath = Join-Path $Global:RepositoryRoot '\output\azdo-dsc-lcm'

    # Find the user's module directory
    $ModuleDirectory = $env:PSModulePath.Split(';') | Where-Object { $_ -like "*$ENV:Username*" -and $_ -like "*documents*" }

    # Install the Dependencies
    Install-Module -Name 'PSDesiredStateConfiguration', 'Datum', 'Datum.InvokeCommand' -ErrorAction Stop -Scope CurrentUser

    # Delete the module from the user's module directory
    Remove-Item -Path (Join-Path $ModuleDirectory -ChildPath 'AzureDevOpsDsc') -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $ModuleDirectory -ChildPath 'azdo-dsc-lcm') -Recurse -Force -ErrorAction SilentlyContinue

    # Copy the module into the user's module directory
    Copy-Item -Path $MockDSCResourceModulePath -Destination $ModuleDirectory -Force -Recurse
    Copy-Item -Path $MockDSCSupportingResourceModulePath -Destination $ModuleDirectory -Force -Recurse
    Copy-Item -Path $LCMModulePath -Destination $ModuleDirectory -Force -Recurse

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

Export-ModuleMember -Function Split-RecurivePath, Get-FunctionPath, Find-Functions, Get-ClassFilePath, Import-Enums, New-MockDirectoryPath, New-MockFilePath, Install-Dependencies, Copy-TestCasesToTempDrive, Get-ModulePath
