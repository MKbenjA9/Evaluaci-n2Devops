[CmdletBinding()]
param(
    [ValidateSet('kind-order-manager-lab','order-manager-eks')]
    [string]$Context = 'kind-order-manager-lab',
    [switch]$CheckPersistence,
    [switch]$KeepPortForwards
)

$ErrorActionPreference = 'Stop'
$ports = if ($Context -eq 'order-manager-eks') { @(28098, 23000, 29090) } else { @(18098, 13000, 19090) }
$api = "http://127.0.0.1:$($ports[0])"
$grafana = "http://127.0.0.1:$($ports[1])"
$prometheus = "http://127.0.0.1:$($ports[2])"
$forwards = @{}
$completed = $false

function Invoke-Kube {
    & kubectl --context $context @args
    if ($LASTEXITCODE -ne 0) { throw 'kubectl failed.' }
}

function Wait-Value($description, [scriptblock]$check) {
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        try {
            $value = & $check
            if ($value) { return $value }
        } catch {
            if ($attempt -eq 29) { throw }
        }
        Start-Sleep -Seconds 2
    }
    throw "Timed out: $description."
}

function Open-Forward($name, $namespace, $ports, $probe) {
    if ($forwards.ContainsKey($name)) {
        $previous = $forwards[$name]
        if (!$previous.HasExited) { Stop-Process -Id $previous.Id }
    }
    $forwardArgs = @('--context',$context,'-n',$namespace,'port-forward','--address','127.0.0.1',"svc/$name",$ports)
    $forwards[$name] = Start-Process -FilePath (Get-Command kubectl).Source -WindowStyle Hidden -PassThru -ArgumentList $forwardArgs
    $null = Wait-Value $name { Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 $probe }
    if ($forwards[$name].HasExited) { throw "Port-forward failed: $name." }
}

function Read-Loki($query, $start) {
    $encoded = [uri]::EscapeDataString($query)
    $uri = "$grafana/api/datasources/proxy/uid/loki/loki/api/v1/query_range?query=$encoded&start=$start"
    (Invoke-RestMethod -Headers $headers -TimeoutSec 5 $uri).data.result
}

function Get-ClaimSnapshot {
    $claims = (Invoke-Kube get pvc -A -o json | ConvertFrom-Json).items |
        Where-Object { $_.metadata.namespace -in 'order-manager','monitoring' }
    if (@($claims).Count -ne 4 -or @($claims | Where-Object { $_.status.phase -ne 'Bound' }).Count) {
        throw 'Expected four Bound PVCs.'
    }
    $claims | ForEach-Object { "$($_.metadata.name) $($_.metadata.uid) $($_.spec.volumeName)" } | Sort-Object
}

try {
    Open-Forward 'order-manager' 'order-manager' "$($ports[0]):8098" "$api/actuator/health"
    Open-Forward 'grafana' 'monitoring' "$($ports[1]):3000" "$grafana/api/health"
    Open-Forward 'prometheus' 'monitoring' "$($ports[2]):9090" "$prometheus/-/ready"
    $secret = Invoke-Kube -n monitoring get secret grafana-auth -o 'jsonpath={.data.password}'
    $password = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($secret))
    $headers = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("admin:$password")) }
    Remove-Variable secret,password

    foreach ($group in '', '/liveness', '/readiness') {
        $health = Invoke-RestMethod "$api/actuator/health$group"
        if ($health.status -ne 'UP') { throw "Health group failed: $group." }
        "/actuator/health$group = UP"
    }
    $probeStart = ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - 1000) * 1000000
    $historyStart = $probeStart - 3600000000000
    1..4 | ForEach-Object { Invoke-RestMethod "$api/api/orders" | Out-Null }
    $status = curl.exe -sS -o NUL -w '%{http_code}' "$api/api/orders/-1"
    if ($LASTEXITCODE -ne 0 -or $status -ne '404') { throw 'Expected order lookup to return HTTP 404.' }
    'GET missing order = HTTP 404'
    $metrics = (Invoke-WebRequest -UseBasicParsing "$api/actuator/prometheus").Content
    $buckets = @($metrics -split [char]10 | Where-Object { $_ -match '^http_server_requests_seconds_bucket\{.*uri="/api/orders"' })
    if (!$buckets.Count) { throw 'HTTP histogram buckets missing.' }
    "HTTP histogram buckets for /api/orders: $($buckets.Count)"
    $target = Wait-Value 'Prometheus target' {
        (Invoke-RestMethod "$prometheus/api/v1/targets").data.activeTargets |
            Where-Object { $_.labels.job -eq 'order-manager' -and $_.health -eq 'up' -and !$_.lastError }
    }
    "Prometheus target $($target.scrapeUrl): $($target.health)"

    $dashboard = Invoke-RestMethod "$grafana/api/dashboards/uid/order-manager-api" -Headers $headers
    $panelIds = @($dashboard.dashboard.panels.id | Sort-Object)
    if (!$dashboard.meta.provisioned -or ($panelIds -join ',') -ne '1,2,3,4,5,6,7,8') {
        throw 'Expected six runtime panels and two CI panels in the provisioned dashboard.'
    }
    $p95 = $dashboard.dashboard.panels | Where-Object { $_.title -like '*p95*' } | Select-Object -First 1
    $encodedP95 = [uri]::EscapeDataString($p95.targets[0].expr)
    $latency = Wait-Value 'Prometheus p95' {
        Invoke-RestMethod "$api/api/orders" | Out-Null
        (Invoke-RestMethod "$prometheus/api/v1/query?query=$encodedP95").data.result |
            Where-Object { $_.value[1] -ne 'NaN' }
    }
    "HTTP p95 measurement: $($latency.value[1]) ms"
    foreach ($uid in 'prometheus','loki') {
        $source = Invoke-RestMethod "$grafana/api/datasources/uid/$uid" -Headers $headers
        $health = Invoke-RestMethod "$grafana/api/datasources/uid/$uid/health" -Headers $headers
        if (!$source.readOnly -or $source.isDefault -ne ($uid -eq 'prometheus') -or $health.status -ne 'OK') {
            throw "Datasource failed: $uid."
        }
        "Grafana $uid = OK, default=$($source.isDefault)"
    }
    "Grafana dashboard: $($dashboard.dashboard.panels.Count) panels"
    $appQuery = '{application="order-manager",service="app",container="api"} |= "event=http_error status=404 category=order_not_found"'
    $dbQuery = '{application="order-manager",service="db",container="postgres"} |= "database system is ready to accept connections"'
    $appLogs = Wait-Value 'API logs in Loki' { Read-Loki $appQuery $probeStart }
    $dbLogs = Wait-Value 'PostgreSQL logs in Loki' { Read-Loki $dbQuery $historyStart }
    "Loki API: $($appLogs.values[0][1])"
    "Loki PostgreSQL: $($dbLogs.values[0][1])"
    $beforeClaims = Get-ClaimSnapshot

    if ($CheckPersistence) {
        $query = [uri]::EscapeDataString('timestamp(up{job="order-manager"})')
        $observed = Wait-Value 'Prometheus historical sample' {
            (Invoke-RestMethod "$prometheus/api/v1/query?query=$query").data.result | Select-Object -First 1
        }
        $anchor = $observed.value[0]
        $sample = $observed.value[1]
        $history = "$prometheus/api/v1/query?query=$query&time=$anchor"
        $customer = "Synthetic persistence probe ($Context)"
        $request = @{ customerName = $customer; items = @() } | ConvertTo-Json -Compress
        $order = Invoke-RestMethod "$api/api/orders" -Method Post -ContentType 'application/json' -Body $request
        if (!$order.id) { throw 'Persistence order was not created.' }
        $marker = 'persistence-' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $body = @{ dashboard = @{ uid = $marker; title = "Verificacion de persistencia ($Context)"; schemaVersion = 39; panels = @() }; overwrite = $false } | ConvertTo-Json -Depth 6
        $null = Invoke-RestMethod "$grafana/api/dashboards/db" -Method Post -Headers $headers -ContentType 'application/json' -Body $body
        $logTimestamp = $appLogs.values[0][0]

        foreach ($workload in 'order-manager/sts/postgres','monitoring/deploy/prometheus','monitoring/deploy/loki','monitoring/deploy/grafana') {
            $namespace,$kind,$name = $workload.Split('/')
            $label = "app.kubernetes.io/name=$name"
            $oldUid = (Invoke-Kube -n $namespace get pods -l $label -o json | ConvertFrom-Json).items[0].metadata.uid
            Invoke-Kube -n $namespace rollout restart "$kind/$name"
            Invoke-Kube -n $namespace rollout status "$kind/$name" --timeout=180s
            $newUid = (Invoke-Kube -n $namespace get pods -l $label -o json | ConvertFrom-Json).items[0].metadata.uid
            if (!$newUid -or $newUid -eq $oldUid) { throw "Pod was not recreated: $name." }
            "$name pod replaced"
        }
        Open-Forward 'grafana' 'monitoring' "$($ports[1]):3000" "$grafana/api/health"
        Open-Forward 'prometheus' 'monitoring' "$($ports[2]):9090" "$prometheus/-/ready"
        $null = Wait-Value 'API readiness after database restart' { Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 "$api/actuator/health/readiness" }
        $restored = Invoke-RestMethod "$api/api/orders/$($order.id)"
        if ($restored.id -ne $order.id -or $restored.customerName -ne $customer) {
            throw 'Database persistence check failed.'
        }
        $saved = Invoke-RestMethod "$grafana/api/dashboards/uid/$marker" -Headers $headers
        if ($saved.meta.provisioned -or $saved.dashboard.uid -ne $marker) { throw 'Grafana persistence check failed.' }
        if ((Invoke-RestMethod $history).data.result[0].value[1] -ne $sample) { throw 'Prometheus persistence check failed.' }
        $null = Wait-Value 'Historical log after Loki restart' {
            Read-Loki $appQuery $probeStart | Where-Object { @($_.values | ForEach-Object { $_[0] }) -contains $logTimestamp }
        }
        $afterClaims = Get-ClaimSnapshot
        if (Compare-Object $beforeClaims $afterClaims) { throw 'PVC or persistent volume changed.' }
        "Persistence passed: PostgreSQL order, Grafana marker $marker, Prometheus sample $sample, Loki log $logTimestamp."
        $afterClaims
    }
    $completed = $true
} finally {
    foreach ($process in $forwards.Values) {
        if ((!$KeepPortForwards -or !$completed) -and !$process.HasExited) { Stop-Process -Id $process.Id }
    }
}
