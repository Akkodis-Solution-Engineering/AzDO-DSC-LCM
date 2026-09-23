task Increment_Version {

    # Write this a better way
    $scriptRoot = "$PSScriptRoot\"
    $outputDirectory = Get-Item "$scriptRoot\..\..\output"

    # A tag-driven release (Release.yml) sets $env:ModuleVersion from the pushed vX.Y.Z tag
    # before this task runs - that tag is authoritative and wins over auto-increment. Every
    # other build (CI Main Build, Nightly Dev Build, local `.\Build.ps1`) has no tag to derive
    # a version from, so those keep auto-incrementing the patch version off the latest git tag.
    if (-not [String]::IsNullOrWhiteSpace($env:ModuleVersion)) {
        $newVersion = $env:ModuleVersion
        Write-Host "Using version $newVersion from `$env:ModuleVersion (tag-driven release)"
    }
    else {
        $latestVersion = & git tag | Where-Object { $_ -match "\d+\.\d+\.\d+" } | Sort-Object -Descending | Select-Object -First 1
        if ([String]::IsNullOrEmpty($latestVersion)) {
            $latestVersion = "0.0.1"
        }

        # Increment the patch version
        $versionParts = $latestVersion -split "\."
        $patchVersion = $versionParts[2]
        $patchVersion = [int]$patchVersion + 1
        $newVersion = "$($versionParts[0]).$($versionParts[1]).$patchVersion"

        Write-Host "Incrementing version from $latestVersion to $newVersion"
    }

    # Update the module manifest
    $templatePath = "$PSScriptRoot\..\..\source\template.ps1"
    $moduleManifestPath = "$PSScriptRoot\..\..\source\DSC.PipelineRunner.Akkodis.psd1"

    if (Test-Path -Path $moduleManifestPath) {
        Remove-Item -Path $moduleManifestPath
    }

    $moduleManifest = Get-Content $templatePath
    $moduleManifest = $moduleManifest -replace "<REPLACE_VERSION>", $newVersion
    Set-Content -Path $moduleManifestPath -Value $moduleManifest

    Write-Host "Version updated in module manifest"
    Write-Host "Outputting new version to $($outputDirectory.FullName)\version.txt"

    # Write the new version to the pipeline variable
    $newVersion | Out-File "$($outputDirectory.FullName)\version.txt" -Encoding utf8 

}