task Package_Module {

    $destinationPath = "$PSScriptRoot\..\..\Output\azdo-dsc-lcm\"
    $outputDirectory = "$PSScriptRoot\..\..\Output\azdo-dsc-lcm.zip"

    # Use Tar to package the module
    Compress-Archive -Path $destinationPath -DestinationPath $outputDirectory -Force

}