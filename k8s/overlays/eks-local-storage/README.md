# EKS estándar con almacenamiento local

Alternativa de demostración para un clúster EKS 1.35 con un Managed Node Group On-Demand de un nodo m6i.large en us-east-1a. La API, PostgreSQL, Prometheus, Grafana, Loki y Alloy reutilizan la base. El provisionador agregó una réplica de infraestructura. El overlay eks-local-storage es independiente de local y eks.

El volumen raíz del nodo puede estar respaldado por EBS. Cada PVC, sin embargo, se monta desde un directorio del sistema de archivos del nodo. El provisionador no invoca AWS para crear o adjuntar un EBS por PVC y no necesita IRSA, Pod Identity ni el add-on EBS CSI. El clúster y el grupo de nodos sí requieren los roles vinculados, el permiso de lanzamiento y la cuota de EC2 del laboratorio. La admisión de los pods auxiliares se prueba antes de desplegar la aplicación. Una prohibición del laboratorio sobre hostPath o sobre el disco del nodo bloquea esta alternativa.

## Capacidad y persistencia

| Uso del disco raíz | Presupuesto de planificación |
|---|---:|
| PVC de PostgreSQL, Prometheus, Loki y Grafana | 17 GiB solicitados, 5 + 5 + 5 + 2 |
| Sistema operativo, kubelet y runtime | 8 GiB |
| Imágenes expandidas y margen de descarga | 12 GiB |
| Logs del runtime y almacenamiento efímero de pods | 5 GiB |
| Margen operativo | 18 GiB |
| Tamaño raíz solicitado | **60 GiB** |

Los valores son estimaciones. local-path-provisioner anuncia la capacidad solicitada en el PV, pero no aplica cuotas por directorio. Todos los componentes comparten espacio e I/O. Verificar espacio e inodos y conservar aproximadamente un 20 % libre. Prometheus ya tiene retención por tiempo y tamaño. Loki tiene siete días de retención por edad. La retención por edad no impone un límite de bytes. [Límites de capacidad de Local Path Provisioner](https://github.com/rancher/local-path-provisioner/blob/v0.0.37/README.md)

| Componente | CPU solicitada/límite | RAM solicitada/límite |
|---|---:|---:|
| API | 250m/750m | 512/768 MiB |
| PostgreSQL | 200m/500m | 256/512 MiB |
| Prometheus | 150m/500m | 256/768 MiB |
| Grafana | 100m/300m | 192/384 MiB |
| Loki | 150m/500m | 384/1.024 MiB |
| Alloy | 75m/250m | 128/256 MiB |
| Provisionador | 50m/200m | 64/128 MiB |

Las seis cargas solicitan 925m y 1.728 MiB. Con el provisionador son 975m y 1.792 MiB, antes del sistema y de los helpers transitorios. Comparar con la capacidad allocatable y las solicitudes de VPC CNI, kube-proxy y CoreDNS. Los límites de CPU agregados exceden los 2 vCPU del nodo. El dimensionamiento supone tráfico bajo de demostración.

Los cuatro componentes con estado usan PV de tipo local y RWO, con afinidad al nodo y WaitForFirstConsumer. Sus pods pueden recrearse en el mismo nodo y volver a montar el directorio. El reemplazo, la terminación o la actualización del nodo puede dejar esos PV inaccesibles y eliminar el disco raíz. Retain conserva la política de reclamación del PV y no cambia el ciclo de vida del disco EC2. Para recuperar en otro nodo se requiere una copia externa y una restauración explícita. [Volúmenes locales de Kubernetes](https://kubernetes.io/docs/concepts/storage/volumes/#local)

## Seguridad y alcance de la prueba

- Rancher Local Path Provisioner v0.0.37 crea helpers transitorios con un montaje hostPath generado por el controlador para crear directorios bajo /opt/order-manager-storage. El controlador se ejecuta sin root, sin capacidades Linux adicionales, con sistema de archivos raíz de solo lectura y sin montaje del host.
- Solo el namespace order-manager-storage tiene el perfil de admisión privileged, necesario para el hostPath del helper. Esta etiqueta no configura contenedores privilegiados. Los helpers se inician sin token de ServiceAccount. No ampliar esta excepción a order-manager o monitoring. Si la política del laboratorio bloquea hostPath o esta etiqueta, detener el despliegue. [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) · [Rancher v0.0.37](https://github.com/rancher/local-path-provisioner/releases/tag/v0.0.37)
- RBAC permite al controlador observar nodos, pods, PVC y StorageClasses, gestionar PV y emitir eventos. La creación de helpers y la lectura de sus logs se limitan a order-manager-storage. La prueba de readiness lista ConfigMaps en ese namespace y la operación get se limita al ConfigMap nombrado. La cuenta de servicio carece de permisos para leer Secrets o modificar RBAC. La capacidad de crear pods con hostPath y administrar PV requiere restringir quién puede modificar el Deployment, la cuenta de servicio, la configuración y el namespace.
- La clase tiene alcance de clúster, selección explícita por PVC y una única ruta configurada. No se activa como predeterminada. Retain y un teardown que solo retira directorios vacíos evitan el borrado recursivo de datos por el helper. En EKS verificar que kubelet aplique el fsGroup de cada pod bajo el montaje local.
- La autorización IAM del grupo no demuestra que Kubernetes acepte el helper. El primer PVC de PostgreSQL y las pruebas de restauración son condiciones para continuar con la demostración.

## Costos en us-east-1

Un EKS en soporte estándar (USD 0,10/h), un m6i.large Linux On-Demand (USD 0,096/h), una IPv4 pública (USD 0,005/h) y un disco raíz de 60 GiB (aprox. USD 0,00658/h si es gp3) dan **USD 0,208/h o USD 0,83 por cuatro horas**. Si el volumen raíz del grupo resulta gp2 a USD 0,10/GiB-mes, son aproximadamente USD 0,209/h o USD 0,84 por cuatro horas. Confirmar el tipo provisionado por el grupo. Los directorios PVC comparten ese disco y no agregan cuatro EBS. Excluye ECR, transferencia y copias de seguridad. El clúster sigue facturando tras retirar el nodo. [EKS](https://aws.amazon.com/eks/pricing/) · [Catálogo regional de EC2 Linux](https://b0.p.awsstatic.com/pricing/2.0/meteredUnitMaps/ec2/USD/current/ec2-ondemand-without-sec-sel/US%20East%20%28N.%20Virginia%29/Linux/index.json) · [EBS](https://aws.amazon.com/ebs/general-purpose/) · [IPv4](https://aws.amazon.com/vpc/pricing/)

## PowerShell para un despliegue autorizado

Ejecutar solo después de la aprobación explícita y con tiempo para retirar los recursos. Trabajar desde la raíz del repositorio. Completar la IPv4 pública del operador y revisar las subredes de la VPC antes de cualquier operación de creación. El kubeconfig nuevo se aísla en un directorio temporal. Mantener la misma sesión entre bloques.

~~~powershell
$ErrorActionPreference = 'Stop'
$Region = 'us-east-1'
$Context = 'order-manager-eks'
$Cluster = $Context
$NodeGroup = 'local-storage'
$Repository = 'order-manager'
$OperatorCidr = 'REPLACE_OPERATOR_IPV4_32'
if ($OperatorCidr -notmatch '^(?:\d{1,3}\.){3}\d{1,3}/32$') { throw 'Indica la IPv4 del operador con /32.' }

function Invoke-Aws {
    & aws --profile default --region $Region @args
    if ($LASTEXITCODE -ne 0) { throw "AWS CLI falló ($LASTEXITCODE)." }
}
function Invoke-Kube {
    $input | & kubectl --context $Context @args
    if ($LASTEXITCODE -ne 0) { throw "kubectl falló ($LASTEXITCODE)." }
}
$Identity = Invoke-Aws sts get-caller-identity --output json | ConvertFrom-Json
$Roles = Invoke-Aws iam list-roles --query 'Roles[].{Name:RoleName,Arn:Arn}' --output json | ConvertFrom-Json
$ClusterRoles = @($Roles | Where-Object Name -Match 'LabEksClusterRole')
$NodeRoles = @($Roles | Where-Object Name -Match 'LabEksNodeRole')
if ($ClusterRoles.Count -ne 1 -or $NodeRoles.Count -ne 1) { throw 'ARN de clúster o nodo ambiguo.' }
$Vpc = Invoke-Aws ec2 describe-vpcs --filters 'Name=is-default,Values=true' --query 'Vpcs[0].VpcId' --output text
$Subnets = Invoke-Aws ec2 describe-subnets --filters "Name=vpc-id,Values=$Vpc" --query 'Subnets[].{Id:SubnetId,AZ:AvailabilityZone,Public:MapPublicIpOnLaunch}' --output json | ConvertFrom-Json
$SubnetA = @($Subnets | Where-Object { $_.AZ -eq 'us-east-1a' -and $_.Public })
$SubnetB = @($Subnets | Where-Object { $_.AZ -eq 'us-east-1b' -and $_.Public })
if ($SubnetA.Count -ne 1 -or $SubnetB.Count -ne 1) { throw 'Confirma dos subredes públicas autorizadas.' }

$Work = Join-Path $env:TEMP ('order-manager-local-storage-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Work | Out-Null
$env:KUBECONFIG = Join-Path $Work 'eks.kubeconfig'
$ClusterFile = Join-Path $Work 'cluster.json'
$NodeFile = Join-Path $Work 'nodegroup.json'
$ClusterInput = Get-Content -Raw k8s/aws/cluster.example.json | ConvertFrom-Json
$ClusterInput.name = $Cluster
$ClusterInput.roleArn = $ClusterRoles[0].Arn
$ClusterInput.resourcesVpcConfig.subnetIds = @($SubnetA[0].Id,$SubnetB[0].Id)
$ClusterInput.resourcesVpcConfig.publicAccessCidrs = @($OperatorCidr)
$ClusterInput.tags.Project = $Cluster
$ClusterInput | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ClusterFile -Encoding Ascii
$NodeInput = Get-Content -Raw k8s/aws/nodegroup-local-storage.example.json | ConvertFrom-Json
$NodeInput.nodeRole = $NodeRoles[0].Arn
$NodeInput.subnets = @($SubnetA[0].Id)
$NodeInput | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $NodeFile -Encoding Ascii
Invoke-Aws eks create-cluster --cli-input-json "file://$ClusterFile" --generate-cli-skeleton output | Out-Null
$NodeFields = (Invoke-Aws eks create-nodegroup --generate-cli-skeleton input | ConvertFrom-Json).PSObject.Properties.Name
if (@($NodeInput.PSObject.Properties.Name | Where-Object { $_ -notin $NodeFields }).Count) {
    throw 'La plantilla contiene campos desconocidos para esta AWS CLI.'
}
~~~

Publicar en un repositorio nuevo de esta ejecución. Evitar reutilizar un repositorio o clúster de otra práctica. Fijar el digest en una copia temporal del overlay, conservando los manifiestos originales.

~~~powershell
$Registry = "$($Identity.Account).dkr.ecr.$Region.amazonaws.com"
$Tag = 'eval3-local-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss')
$Tagged = "$Registry/$($Repository):$Tag"
docker build --platform linux/amd64 -t $Tagged .
if ($LASTEXITCODE -ne 0) { throw 'Falló el build.' }
Invoke-Aws ecr create-repository --repository-name $Repository --image-tag-mutability IMMUTABLE --image-scanning-configuration scanOnPush=true --query repository.repositoryName --output text
Invoke-Aws ecr get-login-password | docker login --username AWS --password-stdin $Registry
if ($LASTEXITCODE -ne 0) { throw 'Falló el login ECR.' }
try {
    docker push $Tagged
    if ($LASTEXITCODE -ne 0) { throw 'Falló el push ECR.' }
} finally {
    docker logout $Registry
}
$Digest = Invoke-Aws ecr describe-images --repository-name $Repository --image-ids "imageTag=$Tag" --query 'imageDetails[0].imageDigest' --output text
~~~

El overlay versionado contiene `registry.invalid` y un digest de ceros para permitir el render de la plantilla. Para una imagen ya publicada y autorizada, usa el host de ECR sin `https://` como `$Registry`, el nombre del repositorio como `$Repository` y el digest de esa imagen como `$Digest`. Puedes verificar el digest con `describe-images` sin volver a compilar ni publicar. Con el directorio temporal `$Work` de esta guía, aplica la configuración solo a su copia y valida el render antes de desplegar.

~~~powershell
if ($Registry -notmatch '^\d{12}\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com(?:\.cn)?$' -or
    $Repository -notmatch '^[a-z0-9]+(?:[._/-][a-z0-9]+)*$' -or
    $Digest -notmatch '^sha256:[a-f0-9]{64}$' -or $Digest -eq ('sha256:' + ('0' * 64))) {
    throw 'Registry, repositorio o digest ECR inválido.'
}
Copy-Item -LiteralPath k8s -Destination $Work -Recurse
$Overlay = Join-Path $Work 'k8s/overlays/eks-local-storage'
$Kustomization = Join-Path $Overlay 'kustomization.yaml'
$Yaml = Get-Content -LiteralPath $Kustomization -Raw
$ImageMapping = '(?m)^(  - name: order-manager\r?\n)    newName: [^\r\n]+\r?\n    digest: [^\r\n]+'
if ([regex]::Matches($Yaml, $ImageMapping).Count -ne 1) { throw 'Bloque de imagen ECR inesperado.' }
$Replacement = "  - name: order-manager`n    newName: $Registry/$Repository`n    digest: $Digest"
[IO.File]::WriteAllText($Kustomization, [regex]::Replace($Yaml, $ImageMapping, $Replacement))
$Render = (Invoke-Kube kustomize $Overlay) -join [Environment]::NewLine
if (!$Render.Contains("$Registry/$Repository@$Digest") -or $Render.Contains('registry.invalid/')) {
    throw 'El overlay no contiene únicamente la referencia de ECR configurada para la API.'
}
$Workloads = Join-Path $Work 'workloads.yaml'
[IO.File]::WriteAllText($Workloads,$Render)
~~~

Desplegar primero el provisionador y PostgreSQL. Esta ruta usa los add-ons estándar de red y DNS del clúster. Comprobar el nodo y los add-ons del sistema antes de continuar. Si falla una validación de infraestructura, registrar el error y pasar al retiro autorizado de los recursos de esta ejecución.

~~~powershell
Invoke-Aws eks create-cluster --cli-input-json "file://$ClusterFile" --query cluster.status --output text
Invoke-Aws eks wait cluster-active --name $Cluster
Invoke-Aws eks create-nodegroup --cli-input-json "file://$NodeFile" --query nodegroup.status --output text
Invoke-Aws eks wait nodegroup-active --cluster-name $Cluster --nodegroup-name $NodeGroup
Invoke-Aws eks update-kubeconfig --name $Cluster --alias $Context --kubeconfig $env:KUBECONFIG
Invoke-Kube wait --for=condition=Ready node --all --timeout=3m
Invoke-Kube -n kube-system get pods
Invoke-Kube get nodes -o 'custom-columns=NAME:.metadata.name,CPU:.status.allocatable.cpu,RAM:.status.allocatable.memory,DISK:.status.allocatable.ephemeral-storage'

Invoke-Kube apply -f k8s/base/namespaces.yaml
$Storage = Join-Path $Overlay 'provisioner.yaml'
$StorageNamespace = ((Get-Content -Raw $Storage) -split '(?m)^---\r?$',2)[0]
$StorageNamespace | Invoke-Kube apply -f -
Invoke-Kube apply --dry-run=server -f $Workloads
Invoke-Kube apply -f $Storage
Invoke-Kube apply -f (Join-Path $Overlay 'storageclass.yaml')
Invoke-Kube -n order-manager-storage rollout status deploy/local-path-provisioner --timeout=3m

$Provisioner = 'system:serviceaccount:order-manager-storage:local-path-provisioner'
$Allowed = kubectl --context $Context -n order-manager-storage auth can-i create pods --as=$Provisioner
$Denied = kubectl --context $Context -n order-manager auth can-i create pods --as=$Provisioner
$Secrets = kubectl --context $Context -n order-manager-storage auth can-i get secrets --as=$Provisioner
if ($Allowed -ne 'yes' -or $Denied -ne 'no' -or $Secrets -ne 'no') { throw 'Permisos del provisionador fuera del alcance esperado.' }

powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File k8s/scripts/New-LabSecrets.ps1 -Context $Context
if ($LASTEXITCODE -ne 0) { throw 'Falló la creación de Secrets.' }
$Postgres = @(($Render -split '(?m)^---\r?$') | Where-Object {
    $_ -match '(?m)^kind: (Service|StatefulSet)\r?$' -and $_ -match '(?m)^  name: postgres\r?$'
})
if ($Postgres.Count -ne 2) { throw 'No se encontraron los recursos de arranque de PostgreSQL.' }
($Postgres -join ([Environment]::NewLine + '---' + [Environment]::NewLine)) | Invoke-Kube apply -f -
Invoke-Kube -n order-manager rollout status sts/postgres --timeout=5m
Invoke-Kube -n order-manager get pvc data-postgres-0
kubectl --context $Context -n order-manager exec sts/postgres -- df -h /var/lib/postgresql/data
if ($LASTEXITCODE -ne 0) { throw 'No se pudo comprobar el disco del PVC.' }

Invoke-Kube apply -f $Workloads
$Chart = @('alloy','alloy','--repo','https://grafana.github.io/helm-charts','--version','1.16.0','--namespace','monitoring','-f','k8s/observability/alloy-values.yaml')
$Alloy = helm template @Chart --kube-version 1.35.0
if ($LASTEXITCODE -ne 0) { throw 'Falló el render de Alloy.' }
$Alloy | Invoke-Kube apply --dry-run=server -f -
helm upgrade --install @Chart --kube-context $Context
if ($LASTEXITCODE -ne 0) { throw 'Falló el despliegue de Alloy.' }

Invoke-Kube -n order-manager rollout status deploy/order-manager --timeout=5m
foreach ($name in 'prometheus','grafana','loki','alloy') {
    Invoke-Kube -n monitoring rollout status "deploy/$name" --timeout=5m
}
Invoke-Kube get pvc -A
Invoke-Kube get pv -o 'custom-columns=NAME:.metadata.name,CLASS:.spec.storageClassName,PATH:.spec.local.path,STATUS:.status.phase'
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File k8s/scripts/Test-Lab.ps1 -Context $Context -CheckPersistence -KeepPortForwards
if ($LASTEXITCODE -ne 0) { throw 'La prueba integral falló.' }
~~~

El resultado esperado es un nodo listo, los seis componentes listos, cuatro PVC Bound con PV local y los mismos PV después de recrear los cuatro pods con estado. Los port-forwards del script se abren en 28098, 23000 y 29090. La prueba verifica el pedido sintético, la muestra de Prometheus, el marcador no aprovisionado de Grafana y el registro histórico en Loki. No usar la terminación del nodo como prueba de persistencia.

## Retiro controlado

Guardar evidencias y respaldar los datos requeridos fuera del nodo antes de retirarlo. Para PostgreSQL se puede generar un pg_dump dentro del pod y copiarlo con kubectl cp a un destino autorizado, comprobando que pueda leerse. Exportar las evidencias de Prometheus, Grafana y Loki antes del retiro. Registrar el ID del nodo, su disco raíz, el digest ECR y la procedencia de cada recurso. Ejecutar la eliminación solo con autorización y el kubeconfig de esta ejecución.

Si el despliegue falló a mitad de camino, consultar el inventario de EKS y ECR y ejecutar solo los pasos para recursos que llegaron a crearse en esta ejecución. Si aún no hay kubeconfig válido, empezar en el primer paso aplicable de AWS.

~~~powershell
# Tras verificar los respaldos y cerrar los port-forwards de esta ejecución.
helm uninstall alloy --namespace monitoring --kube-context $Context
if ($LASTEXITCODE -ne 0) { throw 'Falló el retiro de Alloy.' }
Invoke-Kube delete namespace order-manager monitoring --wait=true --timeout=5m
Invoke-Kube delete -f (Join-Path $Overlay 'provisioner.yaml') --wait=true --timeout=5m
Invoke-Kube delete -f (Join-Path $Overlay 'storageclass.yaml')
Invoke-Aws eks delete-nodegroup --cluster-name $Cluster --nodegroup-name $NodeGroup --query nodegroup.status --output text
Invoke-Aws eks wait nodegroup-deleted --cluster-name $Cluster --nodegroup-name $NodeGroup
Invoke-Aws eks delete-cluster --name $Cluster --query cluster.status --output text
Invoke-Aws eks wait cluster-deleted --name $Cluster
Invoke-Aws eks list-clusters --query clusters --output json
# Si la imagen y el repositorio pertenecen exclusivamente a esta ejecución.
Invoke-Aws ecr batch-delete-image --repository-name $Repository --image-ids "imageDigest=$Digest"
Invoke-Aws ecr delete-repository --repository-name $Repository
~~~

Confirmar en el inventario EC2 que el nodo, el disco raíz y sus interfaces dejaron de facturar. Si quedó un disco o snapshot, comprobar el ID contra el inventario de esta ejecución, su estado y el respaldo antes de pedir autorización para eliminarlo. Los directorios del PV local residen en el disco raíz, por lo que el retiro del nodo puede destruirlos aunque la StorageClass use Retain.
