[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GodotBinary,

    [string]$ResultsDirectory = ".test-results/godot",

    [ValidateRange(1, 1800)]
    [int]$TestTimeoutSeconds = 120
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "../.."))
$testsDirectory = Join-Path $repositoryRoot "tests"
$resultsPath = [IO.Path]::GetFullPath((Join-Path $repositoryRoot $ResultsDirectory))

if (-not (Test-Path -LiteralPath $GodotBinary -PathType Leaf)) {
    throw "Godot executable not found: $GodotBinary"
}
if (-not (Test-Path -LiteralPath $testsDirectory -PathType Container)) {
    throw "Tests directory not found: $testsDirectory"
}

New-Item -ItemType Directory -Force -Path $resultsPath | Out-Null
$tests = @(
    Get-ChildItem -LiteralPath $testsDirectory -File -Filter "*_test.gd" |
        Sort-Object -Property Name
)
if ($tests.Count -eq 0) {
    throw "No Godot test suites matched tests/*_test.gd"
}
if ($tests.Count -lt 53) {
    throw "Expected at least 53 Godot test suites, found $($tests.Count). Check for accidental deletion or renaming."
}

$rows = [Collections.Generic.List[object]]::new()
$failedCount = 0
$temporaryRoot = if ([string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
    [IO.Path]::GetTempPath()
} else {
    $env:RUNNER_TEMP
}
$userDataRoot = Join-Path $temporaryRoot "myth-auction-godot-tests-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Force -Path $userDataRoot | Out-Null

Push-Location $repositoryRoot
try {
    foreach ($test in $tests) {
        $resourcePath = "res://tests/$($test.Name)"
        $logPath = Join-Path $resultsPath "$($test.BaseName).log"
        $stopwatch = [Diagnostics.Stopwatch]::StartNew()

        $startInfo = [Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $GodotBinary
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.ArgumentList.Add("--headless")
        $startInfo.ArgumentList.Add("--path")
        $startInfo.ArgumentList.Add($repositoryRoot)
        $startInfo.ArgumentList.Add("--script")
        $startInfo.ArgumentList.Add($resourcePath)

        # Every suite receives a clean user:// root. This prevents local save files
        # or another suite's fixtures from changing deterministic test outcomes.
        $suiteUserData = Join-Path $userDataRoot $test.BaseName
        $appData = Join-Path $suiteUserData "appdata"
        $localAppData = Join-Path $suiteUserData "localappdata"
        $xdgData = Join-Path $suiteUserData "xdg-data"
        $xdgConfig = Join-Path $suiteUserData "xdg-config"
        $xdgCache = Join-Path $suiteUserData "xdg-cache"
        foreach ($directory in @($appData, $localAppData, $xdgData, $xdgConfig, $xdgCache)) {
            New-Item -ItemType Directory -Force -Path $directory | Out-Null
        }
        $startInfo.Environment["APPDATA"] = $appData
        $startInfo.Environment["LOCALAPPDATA"] = $localAppData
        $startInfo.Environment["XDG_DATA_HOME"] = $xdgData
        $startInfo.Environment["XDG_CONFIG_HOME"] = $xdgConfig
        $startInfo.Environment["XDG_CACHE_HOME"] = $xdgCache

        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        if (-not $process.Start()) {
            throw "Failed to start Godot for $resourcePath"
        }

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($TestTimeoutSeconds * 1000)
        if ($timedOut) {
            $process.Kill($true)
            $process.WaitForExit()
        }

        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $stopwatch.Stop()

        $combinedOutput = @(
            $stdout.TrimEnd()
            $stderr.TrimEnd()
        ) -join [Environment]::NewLine
        [IO.File]::WriteAllText(
            $logPath,
            "$combinedOutput$([Environment]::NewLine)",
            [Text.UTF8Encoding]::new($false)
        )

        $passed = -not $timedOut -and $process.ExitCode -eq 0
        $status = if ($timedOut) {
            "TIMEOUT"
        } elseif ($passed) {
            "PASS"
        } else {
            "FAIL ($($process.ExitCode))"
        }
        if (-not $passed) {
            $failedCount++
        }

        $rows.Add([pscustomobject]@{
            Test       = $test.Name
            Status     = $status
            DurationMs = $stopwatch.ElapsedMilliseconds
            Log        = $logPath
        })

        Write-Host ("{0,-48} {1,12} {2,8} ms" -f $test.Name, $status, $stopwatch.ElapsedMilliseconds)
        if (-not $passed) {
            Write-Host "--- $($test.Name) output ---"
            Get-Content -LiteralPath $logPath -Tail 200
        }
    }
} finally {
    Pop-Location
}

$summaryPath = Join-Path $resultsPath "summary.md"
$summaryLines = [Collections.Generic.List[string]]::new()
$summaryLines.Add("# Godot headless test summary")
$summaryLines.Add("")
$summaryLines.Add("- Suites: $($rows.Count)")
$summaryLines.Add("- Passed: $($rows.Count - $failedCount)")
$summaryLines.Add("- Failed: $failedCount")
$summaryLines.Add("- Per-suite timeout: $TestTimeoutSeconds seconds")
$summaryLines.Add("")
$summaryLines.Add("| Test | Status | Duration (ms) |")
$summaryLines.Add("| --- | ---: | ---: |")
foreach ($row in $rows) {
    $summaryLines.Add("| $($row.Test) | $($row.Status) | $($row.DurationMs) |")
}
[IO.File]::WriteAllLines($summaryPath, $summaryLines, [Text.UTF8Encoding]::new($false))

if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)) {
    Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value (Get-Content -LiteralPath $summaryPath -Raw)
}

Write-Host ""
Write-Host "Godot suites: $($rows.Count), passed: $($rows.Count - $failedCount), failed: $failedCount"
if ($failedCount -ne 0) {
    exit 1
}
