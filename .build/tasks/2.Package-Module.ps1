task Package_Module {

    $destinationPath = "$PSScriptRoot\..\..\output\azdo-dsc-lcm\"
    $outputDirectory = "$PSScriptRoot\..\..\output\azdo-dsc-lcm.zip"

    # Use Tar to package the module
    Compress-Archive -Path $destinationPath -DestinationPath $outputDirectory -Force

}