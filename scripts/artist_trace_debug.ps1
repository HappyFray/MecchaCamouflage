param(
    [int]$Runs = 1,
    [int]$DelaySeconds = 2,
    [int]$ApplyTimeoutSeconds = 300,
    [string]$NativeApplyMode = "artist_trace_parity"
)

$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$RuntimeExe = Join-Path $RepoRoot ".build\bin\meccha-camouflage.exe"
$RuntimeDir = Join-Path $env:LOCALAPPDATA "MecchaCamouflage\runtime"
$StatusPath = Join-Path $RuntimeDir "last_status.json"
$OutDir = Join-Path $RepoRoot ".build\artist-debug"

if (-not (Test-Path $RuntimeExe)) {
    throw "runtime exe not found: $RuntimeExe"
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$JsonlPath = Join-Path $OutDir "artist_trace_debug_$Stamp.jsonl"
$CsvPath = Join-Path $OutDir "artist_trace_debug_$Stamp.csv"
$Summaries = New-Object System.Collections.Generic.List[object]

function Get-MetaValue {
    param(
        [object]$Status,
        [string]$Name,
        [object]$Default = $null
    )
    if ($null -eq $Status -or $null -eq $Status.metadata) {
        return $Default
    }
    $Prop = $Status.metadata.PSObject.Properties[$Name]
    if ($null -eq $Prop) {
        return $Default
    }
    return $Prop.Value
}

function Get-TimingValue {
    param(
        [object]$Status,
        [string]$Name,
        [object]$Default = $null
    )
    if ($null -eq $Status -or $null -eq $Status.timing_ms) {
        return $Default
    }
    $Prop = $Status.timing_ms.PSObject.Properties[$Name]
    if ($null -eq $Prop) {
        return $Default
    }
    return $Prop.Value
}

function Get-LatestRunState {
    param([string]$EventsPath)
    if (-not (Test-Path $EventsPath)) {
        return $null
    }

    $Latest = $null
    $DoneByRun = @{}
    $Lines = Get-Content -Path $EventsPath -Tail 600
    foreach ($Line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($Line)) {
            continue
        }
        try {
            $Event = $Line | ConvertFrom-Json
        } catch {
            continue
        }
        if ([string]::IsNullOrWhiteSpace($Event.run_id)) {
            continue
        }
        if ($Event.event -eq "paint_started") {
            $Latest = $Event
        }
        if ($Event.event -eq "paint_done" -or $Event.event -eq "paint_failed" -or $Event.event -eq "runtime_error") {
            $DoneByRun[$Event.run_id] = $Event
        }
    }
    if ($null -eq $Latest) {
        return $null
    }
    $Done = $DoneByRun.ContainsKey($Latest.run_id)
    return [PSCustomObject]@{
        run_id = $Latest.run_id
        done = $Done
        stage = $Latest.stage
        timestamp = $Latest.timestamp
    }
}

function Get-RunProgressMetrics {
    param(
        [string]$EventsPath,
        [string]$RunId
    )
    $Metrics = [ordered]@{
        dense_elapsed_ms = $null
        dense_hits = $null
        dense_attempts = $null
        hide_gbuffer_elapsed_ms = $null
        template_begin_elapsed_ms = $null
        template_points = $null
        paint_elapsed_ms = $null
        paint_index = $null
        paint_points = $null
        source_path = $null
        brush_radius = $null
        tick_budget_ms = $null
        max_paints_per_tick = $null
        auto_flush_threshold = $null
    }
    if ([string]::IsNullOrWhiteSpace($RunId) -or -not (Test-Path $EventsPath)) {
        return [PSCustomObject]$Metrics
    }

    $Lines = Get-Content -Path $EventsPath -Tail 1200
    foreach ($Line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($Line)) {
            continue
        }
        try {
            $Event = $Line | ConvertFrom-Json
        } catch {
            continue
        }
        if ($Event.run_id -ne $RunId -or $null -eq $Event.details) {
            continue
        }
        $Details = $Event.details
        switch ($Event.stage) {
            "artist_phase0_dense" {
                $Metrics.dense_elapsed_ms = $Details.elapsed_ms
                $Metrics.dense_hits = $Details.dense_hits
                $Metrics.dense_attempts = $Details.dense_attempts
            }
            "artist_phase0_hide_gbuffer_batched" {
                $Metrics.hide_gbuffer_elapsed_ms = $Details.elapsed_ms
                $Metrics.template_points = $Details.template_points
                $Metrics.source_path = $Details.source_path
            }
            "artist_template_load_begin" {
                $Metrics.template_begin_elapsed_ms = $Details.elapsed_ms
                $Metrics.template_points = $Details.template_points
                $Metrics.source_path = $Details.source_path
                $Metrics.brush_radius = $Details.brush_radius
                $Metrics.tick_budget_ms = $Details.paint_tick_budget_ms
                $Metrics.max_paints_per_tick = $Details.max_paints_per_tick
                $Metrics.auto_flush_threshold = $Details.auto_flush_threshold
            }
            "artist_template_load_paint" {
                $Metrics.paint_elapsed_ms = $Details.elapsed_ms
                $Metrics.paint_index = $Details.index
                $Metrics.paint_points = $Details.points
            }
        }
    }
    return [PSCustomObject]$Metrics
}

function First-NonNull {
    param(
        [object]$First,
        [object]$Second
    )
    if ($null -ne $First -and $First -ne "") {
        return $First
    }
    return $Second
}

$EventsPath = Join-Path $RuntimeDir "events.jsonl"
$InitialState = Get-LatestRunState $EventsPath
if ($null -ne $InitialState -and -not $InitialState.done) {
    Write-Host ("[WARN] previous paint run has no completion event run_id={0}; not starting overlapping debug run" -f $InitialState.run_id)
    Write-Host "[WARN] wait for in-game paint to finish, then run make artist-debug again"
    exit 2
}

Write-Host "[INFO] artist trace debug runs=$Runs mode=$NativeApplyMode timeout=${ApplyTimeoutSeconds}s"

for ($Run = 1; $Run -le $Runs; $Run++) {
    Write-Host "[INFO] debug run $Run/$Runs apply started"
    $Start = Get-Date
    $StdoutPath = Join-Path $OutDir ("apply_run_{0}_{1}.stdout.log" -f $Stamp, $Run)
    $StderrPath = Join-Path $OutDir ("apply_run_{0}_{1}.stderr.log" -f $Stamp, $Run)
    $Args = @("--mode", "apply", "--native-apply-mode", $NativeApplyMode)
    $Process = Start-Process -FilePath $RuntimeExe -ArgumentList $Args -PassThru `
        -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath -WindowStyle Hidden
    $TimedOut = -not $Process.WaitForExit($ApplyTimeoutSeconds * 1000)
    if ($TimedOut) {
        Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
        $ExitCode = 124
    } else {
        $ExitCode = $Process.ExitCode
    }
    $End = Get-Date

    $RawStatus = $null
    $Status = $null
    if (Test-Path $StatusPath) {
        $RawStatus = Get-Content -Raw -Path $StatusPath
        $Status = $RawStatus | ConvertFrom-Json
        $RawCopy = Join-Path $OutDir ("last_status_run_{0}_{1}.json" -f $Stamp, $Run)
        Set-Content -Path $RawCopy -Value $RawStatus -Encoding UTF8
    }

    $Response = $Status
    $ControllerElapsed = $null
    $RunId = $null
    if ($null -ne $Status -and $null -ne $Status.last_run) {
        $RunId = $Status.last_run.run_id
        $ControllerElapsed = $Status.last_run.elapsed_ms
        if ($null -ne $Status.last_run.bridge_response) {
            $Response = $Status.last_run.bridge_response
        } else {
            $Response = $Status.last_run
        }
    }
    $ProgressMetrics = Get-RunProgressMetrics $EventsPath $RunId

    $Summary = [PSCustomObject]@{
        run = $Run
        run_id = $RunId
        exit_code = $ExitCode
        timed_out = $TimedOut
        wall_ms = [math]::Round(($End - $Start).TotalMilliseconds, 3)
        success = if ($null -ne $Response) { $Response.success } else { $false }
        stage = if ($null -ne $Response) { $Response.stage } else { "missing_status" }
        message = if ($null -ne $Response) { $Response.message } else { "last_status.json not found" }
        route = Get-MetaValue $Response "route"
        request_mode = Get-MetaValue $Response "request_mode"
        elapsed_ms = if ($null -ne $ControllerElapsed) { $ControllerElapsed } else { Get-MetaValue $Response "elapsed_ms" }
        total_ms = Get-TimingValue $Response "total_ms"
        send_ms = Get-TimingValue $Response "send_ms"
        capture_ms = Get-MetaValue $Response "artist_capture_elapsed_ms"
        capture_resolution = Get-MetaValue $Response "capture_resolution"
        capture_request_width = Get-MetaValue $Response "artist_capture_request_width"
        capture_request_height = Get-MetaValue $Response "artist_capture_request_height"
        base_attempts = Get-MetaValue $Response "artist_base_attempts"
        base_hits = Get-MetaValue $Response "artist_base_hits"
        dense_attempts = First-NonNull (Get-MetaValue $Response "artist_dense_attempts") $ProgressMetrics.dense_attempts
        dense_hits = First-NonNull (Get-MetaValue $Response "artist_dense_hits") $ProgressMetrics.dense_hits
        dense_elapsed_ms = $ProgressMetrics.dense_elapsed_ms
        hide_gbuffer_elapsed_ms = $ProgressMetrics.hide_gbuffer_elapsed_ms
        template_begin_elapsed_ms = $ProgressMetrics.template_begin_elapsed_ms
        lower_rescan_added = Get-MetaValue $Response "artist_lower_rescan_added"
        uv_expand_added = Get-MetaValue $Response "artist_uv_expand_added"
        screen_fill_added = Get-MetaValue $Response "artist_screen_fill_added"
        template_points = First-NonNull (Get-MetaValue $Response "artist_template_points") $ProgressMetrics.template_points
        paint_success = Get-MetaValue $Response "artist_paint_uv_success"
        paint_index = $ProgressMetrics.paint_index
        paint_points = $ProgressMetrics.paint_points
        paint_elapsed_ms = $ProgressMetrics.paint_elapsed_ms
        source_path = First-NonNull (Get-MetaValue $Response "source_path") $ProgressMetrics.source_path
        brush_radius = First-NonNull (Get-MetaValue $Response "artist_brush_radius") $ProgressMetrics.brush_radius
        tick_budget_ms = First-NonNull (Get-MetaValue $Response "artist_paint_tick_budget_ms") $ProgressMetrics.tick_budget_ms
        max_paints_per_tick = First-NonNull (Get-MetaValue $Response "artist_max_paints_per_tick") $ProgressMetrics.max_paints_per_tick
        auto_flush_threshold = First-NonNull (Get-MetaValue $Response "artist_auto_flush_threshold") $ProgressMetrics.auto_flush_threshold
        auto_flush_during_paint = Get-MetaValue $Response "artist_auto_flush_during_paint"
        camera_rotation_source = Get-MetaValue $Response "camera_rotation_source"
        capture_direction_x = Get-MetaValue $Response "capture_direction_x"
        capture_direction_y = Get-MetaValue $Response "capture_direction_y"
        capture_direction_z = Get-MetaValue $Response "capture_direction_z"
        stdout_log = $StdoutPath
        stderr_log = $StderrPath
    }

    $Summaries.Add($Summary) | Out-Null
    $Summary | ConvertTo-Json -Compress -Depth 8 | Add-Content -Path $JsonlPath -Encoding UTF8

    $Ok = if ($TimedOut) { "timeout" } elseif ($Summary.success) { "ok" } else { "fail" }
    Write-Host ("[INFO] debug run {0}/{1} {2} stage={3} elapsed={4}ms capture={5}ms points={6} paint={7} dense={8}/{9}" -f `
        $Run, $Runs, $Ok, $Summary.stage, $Summary.elapsed_ms, $Summary.capture_ms, `
        $Summary.template_points, $Summary.paint_success, $Summary.dense_hits, $Summary.dense_attempts)

    if ($TimedOut) {
        Write-Host "[WARN] apply timed out; native game-thread job may still be running, so remaining runs are skipped"
        break
    }

    if ($Run -lt $Runs -and $DelaySeconds -gt 0) {
        Start-Sleep -Seconds $DelaySeconds
    }
}

$Summaries | Export-Csv -NoTypeInformation -Path $CsvPath -Encoding UTF8

Write-Host ""
Write-Host "[INFO] artist trace debug summary"
$Summaries | Format-Table -AutoSize `
    run, success, timed_out, stage, elapsed_ms, dense_elapsed_ms, hide_gbuffer_elapsed_ms, template_points, paint_index, dense_hits, dense_attempts, brush_radius, max_paints_per_tick

Write-Host "[INFO] wrote $JsonlPath"
Write-Host "[INFO] wrote $CsvPath"
