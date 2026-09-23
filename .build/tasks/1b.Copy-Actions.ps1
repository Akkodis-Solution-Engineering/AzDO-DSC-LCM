
task Copy_Actions {

    $repositoryRoot = Get-Item "$PSScriptRoot\..\..\"
    $sourcePath = "$($repositoryRoot.FullName)\Actions"
    $destinationPath = "$($repositoryRoot.FullName)\output\DSC.PipelineRunner.Akkodis\"
    $newVersion = Get-ChildItem $destinationPath -Directory
    Copy-Item -Path $sourcePath -Destination $newVersion.FullName -Recurse -Force

}
