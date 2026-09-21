<#
    leancheck.ps1 — the project gate.

    Reads lean-formalization.json from the project root and runs, in order:

      1.  lake --no-cache build <buildTargets...> <entryModules...>
      2.  lake env lean --run <leanAuditScript> <library> -- <targets...>
      3.  an axiom-whitelist check over every reported declaration

    It writes evidence under <evidenceDir>/runs/<UTC stamp>-<short id>/
    (report.md, report.json, command-*.log) and replaces LATEST.md with a
    navigation copy. Exit 0 only when every command exited 0, every configured
    target was reported, and every axiom is in the whitelist.

    The script is project-agnostic: everything project-specific comes from
    lean-formalization.json. It never edits the project's sources.

    Usage:
      pwsh -File scripts/leancheck.ps1
      pwsh -File scripts/leancheck.ps1 -NoBuild          # audit only
      pwsh -File scripts/leancheck.ps1 -Config other.json
#>
[CmdletBinding()]
param(
    [string]$Config = 'lean-formalization.json',
    [switch]$NoBuild
)

$ErrorActionPreference = 'Stop'

$projectRoot = (Get-Location).Path
$configPath = if ([System.IO.Path]::IsPathRooted($Config)) { $Config } else { Join-Path $projectRoot $Config }
if (!(Test-Path -LiteralPath $configPath -PathType Leaf)) {
    Write-Host "leancheck: config not found: $configPath" -ForegroundColor Red
    exit 2
}

$cfg = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$library = $cfg.library
if (-not $library) { Write-Host 'leancheck: config has no "library"' -ForegroundColor Red; exit 2 }

$targets      = @($cfg.targets)
$entryModules = @($cfg.entryModules)
$buildTargets = if ($cfg.buildTargets) { @($cfg.buildTargets) } else { @($library) }
$allowed      = @($cfg.allowedAxioms)
$evidenceRoot = if ($cfg.evidenceDir) { Join-Path $projectRoot $cfg.evidenceDir } else { Join-Path $projectRoot 'evidence/lean' }
$lake         = if ($cfg.lakeCommand) { $cfg.lakeCommand } else { 'lake' }
$auditScript  = if ($cfg.leanAuditScript) { $cfg.leanAuditScript } else { 'LeanAudit.lean' }

if ($targets.Count -eq 0) {
    Write-Host 'leancheck: config lists no targets; refusing to report an empty audit as success' -ForegroundColor Red
    exit 2
}

# Some checkouts have `.lake/packages/*` owned by a different account than the one
# running the build; git then fails with "dubious ownership" and exits 128 before
# Lake builds anything. Grant safe.directory FOR THIS INVOCATION ONLY (never in the
# user's global git config). Configure the list in lean-formalization.json.
if ($cfg.gitSafeDirectories -and @($cfg.gitSafeDirectories).Count -gt 0) {
    $dirs = @($cfg.gitSafeDirectories)
    $env:GIT_CONFIG_COUNT = $dirs.Count.ToString()
    for ($i = 0; $i -lt $dirs.Count; $i++) {
        Set-Item -Path ("Env:GIT_CONFIG_KEY_{0}" -f $i) -Value 'safe.directory'
        Set-Item -Path ("Env:GIT_CONFIG_VALUE_{0}" -f $i) -Value ([string]$dirs[$i]).Replace('\', '/')
    }
}

$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$shortId = -join ((1..6) | ForEach-Object { '0123456789abcdef'[(Get-Random -Maximum 16)] })
$runDir = Join-Path $evidenceRoot "runs/$stamp-$shortId"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$results = New-Object System.Collections.ArrayList
$lines   = New-Object System.Collections.ArrayList

function Invoke-Step {
    param([string]$Name, [string]$Exe, [string[]]$Arguments)
    Write-Host "==> $Name"
    $started = Get-Date
    $output = & $Exe @Arguments 2>&1
    $code = $LASTEXITCODE
    $seconds = [int]((Get-Date) - $started).TotalSeconds
    $text = ($output | Out-String)
    Set-Content -LiteralPath (Join-Path $runDir "command-$Name.log") -Value $text -Encoding utf8
    [void]$lines.Add("### $Name (exit $code, ${seconds}s)")
    [void]$lines.Add(($text.TrimEnd()))
    [void]$lines.Add('')
    [void]$results.Add([pscustomobject]@{
        step = $Name; exitCode = $code; seconds = $seconds
        command = "$Exe $($Arguments -join ' ')"
        tail = (($output | Select-Object -Last 8) -join "`n")
    })
    Write-Host "    exit $code in ${seconds}s"
    return $code
}

Push-Location $projectRoot
try {
    if (-not $NoBuild) {
        $buildArgs = @('--no-cache', 'build') + $buildTargets + $entryModules
        [void](Invoke-Step -Name 'build' -Exe $lake -Arguments $buildArgs)
    }
    [void](Invoke-Step -Name 'axiom-audit' -Exe $lake -Arguments (@('env', 'lean', '--run', $auditScript, $library, '--') + $targets))
} finally {
    Pop-Location
}

# ── whitelist check over the reported declarations ──────────────────────────
$reported = @{}
foreach ($line in Get-Content -LiteralPath (Join-Path $runDir 'command-axiom-audit.log') -ErrorAction SilentlyContinue) {
    $idx = $line.IndexOf('LEANCHECK_JSON:')
    if ($idx -lt 0) { continue }
    $decoded = $line.Substring($idx + 'LEANCHECK_JSON:'.Length) | ConvertFrom-Json
    $reported[$decoded.name] = $decoded
}

$failures = New-Object System.Collections.ArrayList
foreach ($target in $targets) {
    if (-not $reported.ContainsKey($target)) { [void]$failures.Add("target not reported: $target"); continue }
    $extra = @($reported[$target].axioms | Where-Object { $allowed -notcontains $_ })
    if ($extra.Count -gt 0) {
        [void]$failures.Add("$target depends on axioms outside the whitelist: $($extra -join ', ')")
    }
}

$stepFailures = @($results | Where-Object exitCode -ne 0)
$ok = ($stepFailures.Count -eq 0) -and ($failures.Count -eq 0)

$report = [pscustomobject]@{
    gate = 'leancheck'; ok = $ok; timestampUtc = $stamp; runId = "$stamp-$shortId"
    projectRoot = $projectRoot; config = $configPath; library = $library
    targets = $targets; allowedAxioms = $allowed
    steps = $results; whitelistFailures = @($failures)
}
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $runDir 'report.json') -Encoding utf8

$md = New-Object System.Collections.ArrayList
[void]$md.Add("# leancheck report — $stamp-$shortId")
[void]$md.Add('')
[void]$md.Add("- project: ``$projectRoot``")
[void]$md.Add("- library: ``$library``")
[void]$md.Add("- targets: $($targets.Count)")
[void]$md.Add("- allowed axioms: ``$($allowed -join ', ')``")
[void]$md.Add("- result: **$(if ($ok) { 'PASS' } else { 'FAIL' })**
")
[void]$md.Add('## steps')
[void]$md.Add('')
[void]$md.Add('| step | exit | seconds |')
[void]$md.Add('|---|---|---|')
foreach ($r in $results) { [void]$md.Add("| $($r.step) | $($r.exitCode) | $($r.seconds) |") }
[void]$md.Add('')
if ($failures.Count -gt 0) {
    [void]$md.Add('## whitelist failures')
    [void]$md.Add('')
    $failures | ForEach-Object { [void]$md.Add("- $_") }
    [void]$md.Add('')
}
[void]$md.Add('## axioms per target')
[void]$md.Add('')
[void]$md.Add('| target | kind | axioms |')
[void]$md.Add('|---|---|---|')
foreach ($target in $targets) {
    if ($reported.ContainsKey($target)) {
        $ax = @($reported[$target].axioms) -join ', '
        [void]$md.Add("| $target | $($reported[$target].kind) | $($ax -replace '\|', '\|') |")
    } else {
        [void]$md.Add("| $target | (missing) | |")
    }
}
Set-Content -LiteralPath (Join-Path $runDir 'report.md') -Value $md -Encoding utf8

# LATEST.md is a navigation copy, never a replacement for the run history.
$latest = New-Object System.Collections.ArrayList
[void]$latest.Add('# leancheck — latest run')
[void]$latest.Add('')
[void]$latest.Add("Latest run: ``$stamp-$shortId`` -> ``$($cfg.evidenceDir)/runs/$stamp-$shortId/report.md``")
[void]$latest.Add('')
[void]$latest.Add("Result: $(if ($ok) { 'PASS' } else { 'FAIL' })")
[void]$latest.Add('')
[void]$latest.Add('History is appended, never erased: every run keeps its own directory.')
Set-Content -LiteralPath (Join-Path $evidenceRoot 'LATEST.md') -Value $latest -Encoding utf8

Write-Host ''
$results | Format-Table step, exitCode, seconds -AutoSize
Write-Host "evidence: $runDir"
if (-not $ok) {
    if ($stepFailures.Count -gt 0) { Write-Host "FAILED steps: $($stepFailures.step -join ', ')" -ForegroundColor Red }
    $failures | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    exit 1
}
Write-Host 'leancheck: PASS'
exit 0
