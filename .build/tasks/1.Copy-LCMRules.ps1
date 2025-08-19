
task Copy_LCM_Rules {

    $repositoryRoot = Get-Item "$PSScriptRoot\..\..\"
    $sourcePath = "$($repositoryRoot.FullName)\LCM Rules"
    $destinationPath = "$($repositoryRoot.FullName)\output\azdo-dsc-lcm\"
    $newVersion = Get-ChildItem $destinationPath -Directory
    #$fullVersionPath = Get-Item -Path $destinationPath.FullName
    Copy-Item -Path $sourcePath -Destination $newVersion.FullName -Recurse -Force

}