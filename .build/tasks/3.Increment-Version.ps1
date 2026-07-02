task Increment_Version {

    # Write this a better way
    $scriptRoot = "$PSScriptRoot\"
    $outputDirectory = Get-Item "$scriptRoot\..\..\output"

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

    # Update the module manifest
    $templatePath = "$PSScriptRoot\..\..\source\template.ps1"
    $moduleManifestPath = "$PSScriptRoot\..\..\source\azdo-dsc-lcm.psd1"

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