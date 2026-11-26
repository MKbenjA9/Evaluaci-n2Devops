[CmdletBinding(DefaultParameterSetName = 'Loopback')]
param(
    [Parameter(Mandatory = $true)]
    [string]$Artifact,
    [Parameter(Mandatory = $true, ParameterSetName = 'Compose')]
    [switch]$Compose,
    [Parameter(ParameterSetName = 'Loopback')]
    [ValidateRange(1, 65535)]
    [int]$LokiPort = 13100
)

$ErrorActionPreference = 'Stop'
$report = Get-Content -LiteralPath $Artifact -Raw | ConvertFrom-Json
if ($report.schema_version -ne 1 -or $report.event -cne 'compose_smoke_success' -or
    $report.commit -cnotmatch '^[a-f0-9]{40}$' -or $report.repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or
    $report.run_id -notmatch '^[1-9][0-9]*$' -or $report.run_attempt -notmatch '^[1-9][0-9]*$' -or
    $report.lines_covered -notmatch '^[0-9]+$' -or $report.lines_missed -notmatch '^[0-9]+$' -or
    $report.compile_seconds -notmatch '^[0-9]+$' -or $null -eq $report.deploy_seconds -or
    $report.deploy_seconds -is [string] -or $report.deploy_seconds -le 0) {
    throw 'El artefacto debe corresponder a un smoke test de Compose exitoso.'
}

$lineCount = [double]$report.lines_covered + [double]$report.lines_missed
if ($lineCount -le 0 -or $null -eq $report.coverage_percent -or
    [Math]::Abs($report.coverage_percent - (100 * $report.lines_covered / $lineCount)) -gt 0.0001) {
    throw 'La cobertura no coincide con los contadores del informe.'
}
$recorded = [DateTimeOffset]::Parse(
    $report.recorded_at, [Globalization.CultureInfo]::InvariantCulture
)
$now = [DateTimeOffset]::UtcNow
if ($recorded -gt $now -or $recorded -lt $now.AddDays(-7)) {
    throw 'La medición queda fuera de los siete días de retención.'
}

$line = [ordered]@{
    coverage_percent = [double]$report.coverage_percent
    deploy_seconds = [double]$report.deploy_seconds
    compile_seconds = [long]$report.compile_seconds
    repository = [string]$report.repository
    commit = [string]$report.commit
    run_id = [long]$report.run_id
    run_attempt = [int]$report.run_attempt
} | ConvertTo-Json -Compress
$entry = [string[]]@([string]($recorded.ToUnixTimeMilliseconds() * 1000000L), $line)
$body = @{ streams = @(@{
    stream = @{ application = 'order-manager'; source = 'github-actions'; event = 'compose_smoke_success' }
    values = ,$entry
}) } | ConvertTo-Json -Depth 8 -Compress

if ($Compose) {
    $body | docker compose exec -T grafana curl --fail --silent --show-error -H 'Content-Type: application/json' --data-binary '@-' http://loki:3100/loki/api/v1/push
    if ($LASTEXITCODE -ne 0) { throw 'Loki rechazó la importación desde Compose.' }
} else {
    Invoke-RestMethod -Method Post -ContentType 'application/json' -Body $body -Uri "http://127.0.0.1:$LokiPort/loki/api/v1/push" | Out-Null
}
Write-Output "Mediciones importadas para la ejecución $($report.run_id), intento $($report.run_attempt)."
