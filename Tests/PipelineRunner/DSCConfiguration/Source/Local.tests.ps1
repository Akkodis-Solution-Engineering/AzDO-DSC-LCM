Describe "Actions/Source/Local Action Tests" -Tag Unit, PipelineRunner, Actions {

    BeforeAll {

        # 'Local.ps1' also exists under Actions/Target/, so filter to the Source action specifically.
        $script:actionPath = (Get-FunctionPath 'Local.ps1' | Where-Object { $_.FullName -match '[\\/]Actions[\\/]Source[\\/]' }).FullName

    }

    Context "When no 'Path' is supplied in the context" {

        It "should throw when the Context hashtable has no Path key" {
            { & $script:actionPath -Context @{} } | Should -Throw "*No 'Path' supplied*"
        }

        It "should throw when Path is an empty string" {
            { & $script:actionPath -Context @{ Path = '' } } | Should -Throw "*No 'Path' supplied*"
        }

        It "should throw when Path is whitespace only" {
            { & $script:actionPath -Context @{ Path = '   ' } } | Should -Throw "*No 'Path' supplied*"
        }

    }

    Context "When the supplied Path does not exist" {

        It "should throw a clear error identifying the missing directory" {
            $missingPath = Join-Path $TestDrive 'does-not-exist'
            { & $script:actionPath -Context @{ Path = $missingPath } } | Should -Throw "*does not exist or is not a directory*"
        }

    }

    Context "When the supplied Path is a file, not a directory" {

        It "should throw" {
            $filePath = Join-Path $TestDrive 'a-file.txt'
            New-Item -Path $filePath -ItemType File -Force | Out-Null

            { & $script:actionPath -Context @{ Path = $filePath } } | Should -Throw "*does not exist or is not a directory*"
        }

    }

    Context "When the supplied Path is a valid directory" {

        BeforeAll {
            $script:validDir = Join-Path $TestDrive 'config-dir'
            New-Item -Path $script:validDir -ItemType Directory -Force | Out-Null
        }

        It "should return the directory unchanged" {
            $result = & $script:actionPath -Context @{ Path = $script:validDir }
            $result | Should -Be $script:validDir
        }

    }

}
