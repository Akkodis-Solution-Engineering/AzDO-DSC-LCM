@{
    PSDependOptions             = @{
        AddToPath  = $true
        Target     = 'output\RequiredModules'
        Parameters = @{}
    }

    InvokeBuild                 = 'latest'
    PSScriptAnalyzer            = 'latest'
    # Pester 6 drops the CoverageGutters coverage format tests.ps1 and build.yaml use.
    Pester                      = '5.7.1'
    ModuleBuilder               = 'latest'
    ChangelogManagement         = 'latest'
    Sampler                     = 'latest'
    MarkdownLinkCheck           = 'latest'


}
