
Describe "Unprotect-SecureString Function Tests" -Tag Unit, PipelineRunner, Auth {

    BeforeAll {

        # Load the functions to test
        $preParseFilePath = (Get-FunctionPath 'Unprotect-SecureString.ps1').FullName
        . $preParseFilePath

    }

    Context "When called with a populated SecureString" {

        It "Round-trips a SecureString back to its plaintext" {
            $secret = 'p@ss-w0rd-123'
            $secure = ConvertTo-SecureString -String $secret -AsPlainText -Force

            Unprotect-SecureString -SecureString $secure | Should -Be $secret
        }

        It "Returns a plain [string] output type" {
            $secure = ConvertTo-SecureString -String 'abc' -AsPlainText -Force

            $result = Unprotect-SecureString -SecureString $secure

            $result | Should -BeOfType ([string])
        }
    }

    Context "When called with an empty SecureString" {

        It "Returns an empty string" {
            # ConvertTo-SecureString rejects an empty -String, so build the empty
            # SecureString directly to exercise the empty-credential path.
            $secure = [System.Security.SecureString]::new()

            Unprotect-SecureString -SecureString $secure | Should -Be ''
        }
    }

    Context "When called without a SecureString" {

        It "Throws because the parameter is mandatory" {
            { Unprotect-SecureString -SecureString $null } | Should -Throw
        }
    }
}
