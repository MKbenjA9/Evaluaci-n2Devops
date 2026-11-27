[CmdletBinding()]
param(
    [ValidateSet('kind-order-manager-lab','order-manager-eks')]
    [string]$Context = 'kind-order-manager-lab'
)

$ErrorActionPreference = 'Stop'
$random = [Security.Cryptography.RandomNumberGenerator]::Create()
try {
    foreach ($target in @(
        @{ Namespace = 'order-manager'; Name = 'postgres-auth'; Data = @{ username = 'orderuser' } }
        @{ Namespace = 'monitoring'; Name = 'grafana-auth'; Data = @{} }
    )) {
        $existing = kubectl --context $context -n $target.Namespace get secret $target.Name --ignore-not-found -o name
        if ($LASTEXITCODE -ne 0) { throw "No se pudo consultar $($target.Name)." }
        if ($existing) { continue }

        $bytes = New-Object byte[] 32
        $random.GetBytes($bytes)
        $target.Data.password = [Convert]::ToBase64String($bytes)
        @{
            apiVersion = 'v1'
            kind = 'Secret'
            metadata = @{ namespace = $target.Namespace; name = $target.Name }
            type = 'Opaque'
            stringData = $target.Data
        } | ConvertTo-Json -Depth 5 -Compress | kubectl --context $context create -f -
        if ($LASTEXITCODE -ne 0) { throw "No se pudo crear $($target.Name)." }
    }
} finally {
    $random.Dispose()
}
