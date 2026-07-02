task Copy_ChangeLog {

    $sourcePath = Get-Item "$PSScriptRoot\..\..\CHANGELOG.md" 
    $moduleDestinationPath = Get-Item "$PSScriptRoot\..\..\output\azdo-dsc-lcm\"
    $outputDestinationPath = Get-Item "$PSScriptRoot\..\..\output\"

    Copy-Item -Path $sourcePath.FullName -Destination $moduleDestinationPath.FullName -Force
    Copy-Item -Path $sourcePath.FullName -Destination $outputDestinationPath.FullName -Force

}