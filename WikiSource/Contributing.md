# Contributing

This page covers the wiki itself and how it is built. For the module's own contribution
checks — tests, coverage floor, lint — run `tests.ps1` and `Build.ps1 -Tasks build` in the
repository root, as `.github/workflows/ci-main-build.yml` and `Main.CodeCoverage.yml` do.

## The wiki is generated

**Do not edit these pages in the GitHub wiki UI.** The wiki is overwritten wholesale on every
release; an edit made in the UI is lost the next time a tag is pushed.

The source of truth is `WikiSource/` in the main repository. Edit there, open a pull request,
and the change reaches the wiki with the next release.

```
WikiSource/
├── .pageorder          # sidebar order — one page name per line
├── Home.md
├── Getting-Started.md
└── ...                 # one .md per conceptual page
```

## How a page becomes a wiki page

`scripts/Build-WikiContent.ps1` compiles `WikiSource/` plus the module's own comment-based
help into a directory of wiki pages:

```
scripts/Build-WikiContent.ps1
 ├─ Copy every WikiSource/*.md verbatim
 ├─ Generate Command-<Name>.md per exported function, from its comment-based help
 ├─ Generate Command-Reference.md — the index of those pages
 ├─ Generate _Sidebar.md from .pageorder plus the command pages
 └─ Generate _Footer.md — module version and build date
```

Run it locally:

```powershell
./scripts/Build-WikiContent.ps1 -Verbose
```

It returns an object describing what it produced:

```
OutputPath       : /home/user/DSC.PipelineRunner.Akkodis/output/WikiContent
ModuleVersion    : 1.0.0
ConceptualPages  : 13
CommandPages     : 7
TotalPages       : 22
```

Override the paths when you want the output somewhere else:

```powershell
./scripts/Build-WikiContent.ps1 -OutputPath /tmp/wiki -ModuleVersion 1.2.3
```

The output directory is deleted and recreated on every run, so a page you removed from
`WikiSource/` does not linger.

### Command pages are read from the AST

Command help is extracted by parsing each `source/Public/*.ps1` file with
`[System.Management.Automation.Language.Parser]`, finding the function definition and calling
`GetHelpContent()` on it. Parameter types and mandatory flags come from the parsed parameter
block.

This matters: **the module is never imported**. The wiki therefore builds on a clean agent with
no resolved dependencies, which is what makes it usable as a per-pull-request check rather than
only a release step.

## The build fails loudly

The script throws rather than producing a half-built wiki. Each of these is a build failure:

| Condition | Why |
| --- | --- |
| `WikiSource/` is missing or empty | Nothing to publish. |
| An exported command has no source file under `source/Public/` | The manifest and the source have drifted. |
| A source file contains no function definition | Cannot generate a page. |
| An exported command has no `.SYNOPSIS` | An empty command page is worse than a failed build. |
| No pages were generated | Something is wrong with the inputs. |
| `.pageorder` is missing | The sidebar would be arbitrary. |
| A page in `WikiSource/` is not listed in `.pageorder` | Navigation would silently lose it. |
| A `.pageorder` entry has no matching page | The sidebar would carry a dead link. |

The last two are the ones that catch you when adding a page: create the `.md` **and** add the
name to `.pageorder`, or the build fails.

## Adding a page

1. Write `WikiSource/My-Page.md`, starting with a single `# H1` — the sidebar uses that H1 as
   the link text.
2. Add `My-Page` to `.pageorder`, in the position you want it in the sidebar.
3. Run `./scripts/Build-WikiContent.ps1` and read the output.
4. Link to it from a related page, and from `Home.md`'s "Where to start" table if it is a
   top-level topic.

Page names become wiki URLs verbatim, so use `Title-Case-With-Hyphens` and link with
`[Text](My-Page)` — no `.md` extension.

## Documenting a new command

Nothing to do in `WikiSource/`. Add the function to `source/Public/`, export it from the
manifest, and give it comment-based help:

```powershell
<#
.SYNOPSIS
One line. Required — the build fails without it.

.DESCRIPTION
What it does and when to reach for it.

.PARAMETER Path
What this parameter is for.

.EXAMPLE
Invoke-Thing -Path C:\x
What that does, in a sentence.
#>
function Invoke-Thing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )
}
```

`Command-Invoke-Thing.md`, its entry in `Command-Reference.md`, and its sidebar link are all
generated from that.

## When the wiki is built, and when it is published

Building and publishing are two different things, run at two different times, with two
different failure postures.

**Built on every pull request — blocking.** `.github/workflows/Wiki.yml` runs
`scripts/Build-WikiContent.ps1` on every PR and uploads the result as an artifact. Because the
script reads help from the AST rather than importing the module, that job needs nothing but a
checkout and `pwsh` — no dependency resolution, no build. Every invariant in the table above is
therefore enforced at review time: a page you forgot to add to `.pageorder`, a `.pageorder`
entry whose page you deleted, or a new exported command with no `.SYNOPSIS` fails the PR that
introduced it, on the commit that introduced it.

**Compiled and published on a full release — non-fatal.** `.github/workflows/Release.yml` runs
`./build.ps1 -Tasks Build_Wiki_Content, Publish_Wiki_Content` after the release itself, gated on
`IsPrerelease == 'false'`. A preview tag ships to the Gallery without moving the wiki, so the
published wiki always describes the latest released version rather than a preview most consumers
never install.

Both tasks are local to `.build/tasks/5.Build-Wiki.ps1`. `build.yaml`'s `GitHubConfig` section
still names a `Publish_GitHub_Wiki_Content` publish step — that is unrelated Sampler/DSC-community
boilerplate this repo does not act on; the publish is only a clone of `<owner>/<repo>.wiki.git`, a
mirror-copy, a commit and a push, written directly rather than through `DscResource.DocGenerator`,
which this module does not depend on.

Neither task is chained into `build.yaml`'s `build` or `publish` workflow, for two reasons stated
there:

- the repository wiki has to be enabled and initialised before anything can be pushed to it;
- a wiki failure must never fail a release whose Gallery package has already been published.

`Publish_Wiki_Content` therefore never throws. Every outcome — published, already up to date, no
token, wiki not initialised, push rejected — is written to the run summary and the task exits
clean. That is deliberate: the step used to be `continue-on-error: true`, which reported a hard
`exit code 1` as a green check. A wiki that fails to *publish* leaves the release intact and the
next full tag republishes it. A wiki that fails to *build* has already stopped the PR that broke
it, well before this point.

## Style

Existing pages hold to a few things worth matching:

- **Examples over prose.** Every property, setting and accessor gets at least one worked YAML
  or PowerShell block. Several, where the shapes differ meaningfully.
- **Quote real messages.** Error text in this wiki is copied from the source, not paraphrased,
  so searching for a message you saw in a log lands on the page that explains it.
- **Say what is not true.** Where behaviour is surprising — `Test` mode drift is `FAIL`,
  `variables()` returns `$null` but `parameters()` throws, `PartialSuccess` does not fail a
  build — say so explicitly rather than leaving it to be inferred.
- **Mark what is not implemented.** If you document a design that has not shipped, label it.
  A reader cannot tell a plan from a feature by reading the page.

## Checking a change before you open the PR

```powershell
# The wiki compiles, and .pageorder agrees with the pages on disk.
./scripts/Build-WikiContent.ps1 -Verbose

# Read a generated page.
Get-Content ./output/WikiContent/Command-Invoke-DscRunner.md

# The module's own gates.
. ./tests.ps1
```

A wiki-only change is still ordinary PowerShell in the repository — `scripts/Build-WikiContent.ps1`
and `.build/tasks/5.Build-Wiki.ps1` are picked up by `Build.ps1 -Tasks build` like any other build
task, and `.github/workflows/Wiki.yml` runs on every pull request regardless of which files it
touched.
