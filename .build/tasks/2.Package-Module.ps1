task Package_Module {

    $destinationPath = "$PSScriptRoot\..\..\Output\azdo-dsc-lcm\"
    $outputDirectory = "$PSScriptRoot\..\..\Output\"

    if ($IsWindows) {
        throw "This task is not supported on Windows"
    }

    # Use Tar to package the module
    Push-Location $outputDirectory
    zip "azdo-dsc-lcm.zip" ".\azdo-dsc-lcm\" -r
    Pop-Location

}