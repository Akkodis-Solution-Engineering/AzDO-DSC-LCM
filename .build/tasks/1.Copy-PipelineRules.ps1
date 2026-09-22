
task Copy_Pipeline_Rules {

    $repositoryRoot = Get-Item "$PSScriptRoot\..\..\"
    $sourcePath = "$($repositoryRoot.FullName)\Pipeline Rules"
    $destinationPath = "$($repositoryRoot.FullName)\output\DSC.PipelineRunner.Akkodis\"
    $newVersion = Get-ChildItem $destinationPath -Directory
    #$fullVersionPath = Get-Item -Path $destinationPath.FullName
    Copy-Item -Path $sourcePath -Destination $newVersion.FullName -Recurse -Force

}