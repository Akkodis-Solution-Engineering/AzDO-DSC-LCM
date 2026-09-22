task Package_Module {

    $destinationPath = "$PSScriptRoot\..\..\output\DSC.PipelineRunner.Akkodis\"
    $outputDirectory = "$PSScriptRoot\..\..\output\DSC.PipelineRunner.Akkodis.zip"

    # Use Tar to package the module
    Compress-Archive -Path $destinationPath -DestinationPath $outputDirectory -Force

}