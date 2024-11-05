task Copy_ChangeLog {

    $sourcePath = "$PSScriptRoot\..\..\CHANGELOG.md" 
    $moduleDestinationPath = "$PSScriptRoot\..\..\Output\azdo-dsc-lcm\"
    $outputDestinationPath = "$PSScriptRoot\..\..\Output\"

    Copy-Item -Path $sourcePath -Destination $moduleDestinationPath -Force
    Copy-Item -Path $sourcePath -Destination $outputDestinationPath -Force

}