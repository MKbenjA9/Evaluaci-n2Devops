# Order Manager en EKS Auto Mode

Estos comandos corresponden a la fase 2. Antes de ejecutarlos se necesita aprobación explícita, una sesión con tiempo suficiente para desplegar y retirar los recursos, y la confirmación de IAM por parte del laboratorio.

## Condiciones de inicio

- AWSServiceRoleForAmazonEKS estaba ausente. La simulación de voclabs para que EKS lo aprovisione devolvió allowed al apuntar al ARN exacto del rol y usar el contexto de EKS. Confirmar que el laboratorio permite su aprovisionamiento durante CreateCluster.
- Confirmar que el rol de nodo autorizado cumple los permisos de Auto Mode. Su simulación devolvió allowed para lectura de ECR y explicitDeny para eks-auth:AssumeRoleForPodIdentity. Solicitar revisión al laboratorio. El despliegue de la aplicación no prevé asociaciones Pod Identity.
- El rol de clúster incluye AmazonEKSBlockStoragePolicy. La guía actual de AWS lista AmazonEKSBlockStoragePolicyV2 o permisos equivalentes. La simulación básica de ec2:CreateVolume, AttachVolume y DeleteVolume dio allowed, pero no valida el flujo real, las condiciones de recursos o los controles de la organización. Confirmar la compatibilidad con el laboratorio antes de crear el clúster.
- Comprobar el saldo y el tiempo en Learner Lab. Con 03:22 restantes, reservar tiempo para retirar los recursos o iniciar una sesión autorizada con margen suficiente. La tarifa EKS continúa aunque se retire el nodo.

## Configuración y costo previsto

Se usarán dos subredes públicas en us-east-1a y us-east-1b para el plano de control, con acceso privado activo y acceso público restringido a la IPv4 del operador con máscara /32. El nodo usará la subred de us-east-1a y una IPv4 pública para salida a los registros de imágenes por el Internet Gateway. Los Services son ClusterIP y los accesos de prueba se hacen mediante port-forward en loopback. Se habilita la capacidad de balanceo que exige la configuración de Auto Mode. Los manifiestos no solicitan un LoadBalancer ni un Ingress.

El NodePool usa m6i.large On-Demand, con un límite de 2 vCPU y 8 GiB. El límite de aprovisionamiento es eventual y el reemplazo de un nodo puede producir solapamiento temporal. El disco de nodo tiene 30 GiB y los PVC suman 17 GiB. La clase gp3 está cifrada, usa WaitForFirstConsumer y conserva los volúmenes tras retirar las reclamaciones. El controlador integrado de Auto Mode gestiona EBS.

| Concepto | USD por hora estimados |
|---|---:|
| Plano de control en soporte estándar | 0,10000 |
| EC2 m6i.large Linux | 0,09600 |
| Gestión de Auto Mode para m6i.large | 0,01152 |
| Una IPv4 pública de nodo | 0,00500 |
| gp3, 47 GiB a 0,08 USD/GiB-mes, prorrateados en 730 h | 0,00515 |
| Total aproximado por hora | 0,21767 |
| Total aproximado por cuatro horas | 0,87 |

La estimación excluye ECR, transferencia, snapshots y almacenamiento retenido tras la prueba. [Precios de EKS](https://aws.amazon.com/eks/pricing/) · [Catálogo regional de Auto Mode](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonEKS/current/us-east-1/index.json) · [Catálogo regional de EC2 Linux](https://b0.p.awsstatic.com/pricing/2.0/meteredUnitMaps/ec2/USD/current/ec2-ondemand-without-sec-sel/US%20East%20%28N.%20Virginia%29/Linux/index.json) · [EBS](https://aws.amazon.com/ebs/general-purpose/) · [IPv4](https://aws.amazon.com/vpc/pricing/) · [ECR](https://aws.amazon.com/ecr/pricing/)

## PowerShell para una ejecución autorizada

Abrir una sesión PowerShell en la raíz del repositorio. Mantener los bloques en la misma sesión y detenerse si un comando falla. Completar $OperatorCidr con la IPv4 pública de trabajo.

~~~powershell
$ErrorActionPreference = 'Stop'
$Region = 'us-east-1'
$Context = 'order-manager-eks'
$Cluster = $Context
$Repository = 'order-manager'
$OperatorCidr = 'REPLACE_OPERATOR_IPV4_32'
if ($OperatorCidr -notmatch '^(?:\d{1,3}\.){3}\d{1,3}/32$') { throw 'Configura la IPv4 pública del operador con /32.' }

function Invoke-Aws {
    & aws --profile default --region $Region @args
    if ($LASTEXITCODE -ne 0) { throw "AWS CLI terminó con código $LASTEXITCODE." }
}
function Invoke-Kube {
    $input | & kubectl --context $Context @args
    if ($LASTEXITCODE -ne 0) { throw "kubectl terminó con código $LASTEXITCODE." }
}

$identity = Invoke-Aws sts get-caller-identity --output json | ConvertFrom-Json
$roles = Invoke-Aws iam list-roles --query 'Roles[].{Name:RoleName,Arn:Arn}' --output json | ConvertFrom-Json
$clusterRoles = @($roles | Where-Object Name -Match 'LabEksClusterRole')
$nodeRoles = @($roles | Where-Object Name -Match 'LabEksNodeRole')
if ($clusterRoles.Count -ne 1 -or $nodeRoles.Count -ne 1) { throw 'El laboratorio debe identificar un rol de cada tipo.' }
$plannedClusterArn = "arn:aws:eks:${Region}:$($identity.Account):cluster/$Cluster"
$nodeDecision = Invoke-Aws iam simulate-principal-policy --policy-source-arn $nodeRoles[0].Arn --action-names eks-auth:AssumeRoleForPodIdentity --resource-arns $plannedClusterArn --context-entries "ContextKeyName=aws:RequestedRegion,ContextKeyValues=$Region,ContextKeyType=string" --query 'EvaluationResults[0].EvalDecision' --output text
if ($nodeDecision -ne 'allowed') { throw 'El rol de nodo todavía no cumple el requisito IAM de Auto Mode.' }
$slr = & aws --profile default --region $Region iam get-role --role-name AWSServiceRoleForAmazonEKS --query Role.RoleName --output text 2>$null
if ($LASTEXITCODE -ne 0) {
    $callerRole = @($roles | Where-Object Name -eq 'voclabs')
    if ($callerRole.Count -ne 1) { throw 'No se identificó el principal IAM del laboratorio.' }
    $slrArn = "arn:aws:iam::$($identity.Account):role/aws-service-role/eks.amazonaws.com/AWSServiceRoleForAmazonEKS"
    $decision = Invoke-Aws iam simulate-principal-policy --policy-source-arn $callerRole[0].Arn --action-names iam:CreateServiceLinkedRole --resource-arns $slrArn --context-entries 'ContextKeyName=iam:AWSServiceName,ContextKeyValues=eks.amazonaws.com,ContextKeyType=string' "ContextKeyName=aws:RequestedRegion,ContextKeyValues=$Region,ContextKeyType=string" --query 'EvaluationResults[0].EvalDecision' --output text
    if ($decision -ne 'allowed') { throw 'El laboratorio debe resolver el rol vinculado de EKS.' }
}
$vpc = Invoke-Aws ec2 describe-vpcs --filters 'Name=is-default,Values=true' --query 'Vpcs[0].VpcId' --output text
$subnets = Invoke-Aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc" --query 'Subnets[].{Id:SubnetId,AZ:AvailabilityZone,Public:MapPublicIpOnLaunch}' --output json | ConvertFrom-Json
$subnetA = @($subnets | Where-Object { $_.AZ -eq 'us-east-1a' -and $_.Public })
$subnetB = @($subnets | Where-Object { $_.AZ -eq 'us-east-1b' -and $_.Public })
if ($subnetA.Count -ne 1 -or $subnetB.Count -ne 1) { throw 'Selecciona las dos subredes autorizadas de forma explícita.' }

$Work = Join-Path $env:TEMP ('order-manager-eks-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Work | Out-Null
$env:KUBECONFIG = Join-Path $Work 'eks.kubeconfig'
$inputFile = Join-Path $Work 'cluster.json'
$clusterInput = Get-Content -Raw k8s/aws/cluster-auto.example.json | ConvertFrom-Json
$clusterInput.roleArn = $clusterRoles[0].Arn
$clusterInput.resourcesVpcConfig.subnetIds = @($subnetA[0].Id, $subnetB[0].Id)
$clusterInput.resourcesVpcConfig.publicAccessCidrs = @($OperatorCidr)
$clusterInput | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $inputFile -Encoding ASCII
Invoke-Aws eks create-cluster --cli-input-json "file://$inputFile" --generate-cli-skeleton output | Out-Null
~~~

Publicar una imagen de la evaluación con una etiqueta inmutable y capturar su digest. El login recibe el token por stdin. Reutilizar el nombre del repositorio solo si se confirma que pertenece a esta ejecución.

~~~powershell
$Registry = "$($identity.Account).dkr.ecr.$Region.amazonaws.com"
$Tag = 'eval3-' + (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss')
$Tagged = "$Registry/${Repository}:${Tag}"
Invoke-Aws ecr create-repository --repository-name $Repository --image-tag-mutability IMMUTABLE --image-scanning-configuration scanOnPush=true --query repository.repositoryName --output text
docker build --platform linux/amd64 -t $Tagged .
if ($LASTEXITCODE -ne 0) { throw 'Falló el build Docker.' }
Invoke-Aws ecr get-login-password | docker login --username AWS --password-stdin $Registry
if ($LASTEXITCODE -ne 0) { throw 'Falló el inicio de sesión en ECR.' }
try {
    docker push $Tagged
    if ($LASTEXITCODE -ne 0) { throw 'Falló la publicación.' }
} finally {
    docker logout $Registry
}
$Digest = Invoke-Aws ecr describe-images --repository-name $Repository --image-ids "imageTag=$Tag" --query 'imageDetails[0].imageDigest' --output text
if ($Digest -notmatch '^sha256:[a-f0-9]{64}$') { throw 'Digest inválido.' }
$Image = "$Registry/$Repository@$Digest"
~~~

Fijar el digest en el overlay EKS tras publicar la imagen. Si el overlay ya contiene una sección images, revisar el digest existente antes de sustituirlo. Luego crear el clúster y autorizar al rol de nodo para la clase personalizada.

~~~powershell
$overlay = 'k8s/overlays/eks/kustomization.yaml'
if ((Get-Content -Raw $overlay) -notmatch '(?m)^images:') {
    Add-Content -LiteralPath $overlay -Encoding Ascii -Value @(
        '', 'images:', '  - name: order-manager', "    newName: $Registry/$Repository", "    digest: $Digest"
    )
}
$render = (Invoke-Kube kustomize k8s/overlays/eks) -join [Environment]::NewLine
if (!$render.Contains($Image)) { throw 'El overlay no apunta al digest publicado.' }
$renderFile = Join-Path $Work 'workloads.yaml'
[IO.File]::WriteAllText($renderFile,$render)

Invoke-Aws eks create-cluster --cli-input-json "file://$inputFile" --query 'cluster.status' --output text
Invoke-Aws eks wait cluster-active --name $Cluster
Invoke-Aws eks update-kubeconfig --name $Cluster --alias $Context --kubeconfig $env:KUBECONFIG
Invoke-Aws eks create-access-entry --cluster-name $Cluster --principal-arn $nodeRoles[0].Arn --type EC2 --query 'accessEntry.type' --output text
Invoke-Aws eks associate-access-policy --cluster-name $Cluster --principal-arn $nodeRoles[0].Arn --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSAutoNodePolicy --access-scope type=cluster | Out-Null
Invoke-Kube api-resources --api-group eks.amazonaws.com
Invoke-Kube api-resources --api-group karpenter.sh

$securityGroup = Invoke-Aws eks describe-cluster --name $Cluster --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text
$compute = (Get-Content -Raw k8s/aws/compute-auto.example.yaml).Replace('REPLACE_NODE_ROLE_NAME',$nodeRoles[0].Name).Replace('REPLACE_SUBNET_1A',$subnetA[0].Id).Replace('REPLACE_CLUSTER_SECURITY_GROUP',$securityGroup)
$compute | Invoke-Kube apply --dry-run=server -f -
$compute | Invoke-Kube apply -f -
Invoke-Kube wait --for=condition=Ready nodeclass/order-manager --timeout=120s

Invoke-Kube apply -f k8s/base/namespaces.yaml
Invoke-Kube apply --dry-run=server -f $renderFile
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File k8s/scripts/New-LabSecrets.ps1 -Context $Context
if ($LASTEXITCODE -ne 0) { throw 'Falló la creación de Secrets.' }
$first = @(($render -split '(?m)^---\r?$') | Where-Object {
    $_ -match '(?m)^kind: StorageClass\r?$' -or
    ($_ -match '(?m)^kind: (Service|StatefulSet)\r?$' -and $_ -match '(?m)^  name: postgres\r?$')
})
if ($first.Count -ne 3) { throw 'No se identificaron StorageClass, Service y StatefulSet de PostgreSQL.' }
($first -join ([Environment]::NewLine + '---' + [Environment]::NewLine)) | Invoke-Kube apply -f -
Invoke-Kube -n order-manager rollout status sts/postgres --timeout=12m
Invoke-Kube apply -f $renderFile

$Chart = @('alloy','alloy','--repo','https://grafana.github.io/helm-charts','--version','1.16.0','--namespace','monitoring','-f','k8s/observability/alloy-values.yaml')
$alloy = helm template @Chart --kube-version 1.35.0
if ($LASTEXITCODE -ne 0) { throw 'No se pudo renderizar Alloy.' }
$alloy | Invoke-Kube apply --dry-run=server -f -
helm upgrade --install @Chart --kube-context $Context
if ($LASTEXITCODE -ne 0) { throw 'Falló el despliegue de Alloy.' }
Invoke-Kube -n order-manager rollout status deploy/order-manager --timeout=5m
foreach ($component in 'prometheus','grafana','loki','alloy') {
    Invoke-Kube -n monitoring rollout status "deploy/$component" --timeout=5m
}
~~~

Comprobar un nodo operativo, seis pods listos y cuatro PVC enlazados con el provisionador Auto Mode. Revisar eventos y NodeClaims si algún pod permanece Pending. El script comprueba Actuator, 404, métricas, fuentes de Grafana y logs de Loki y persistencia tras recrear pods. Cerrar los port-forwards de la ejecución AWS antes de repetirlo. Los puertos de kind quedan reservados para ese entorno.

~~~powershell
Invoke-Kube get nodes,nodeclaims
Invoke-Kube -n order-manager get pods,deploy,sts,svc,pvc
Invoke-Kube -n monitoring get pods,deploy,svc,pvc
Invoke-Kube get pv
Invoke-Kube -n order-manager auth can-i get pods --subresource=log --as=system:serviceaccount:monitoring:alloy
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File k8s/scripts/Test-Lab.ps1 -Context $Context -CheckPersistence -KeepPortForwards
if ($LASTEXITCODE -ne 0) { throw 'La validación integral no pasó.' }
~~~

- [API AWS mediante port-forward](http://127.0.0.1:28098/actuator/health)
- [Prometheus AWS mediante port-forward](http://127.0.0.1:29090/targets)
- [Dashboard AWS mediante port-forward](http://127.0.0.1:23000/d/order-manager-api) y [Explore](http://127.0.0.1:23000/explore)

## Retiro controlado

Anotar el repositorio, digest, NodeClaims y los cuatro identificadores EBS antes de retirar recursos. Exportar las evidencias y respaldar los datos requeridos. Ejecutar el siguiente bloque solo con autorización de eliminación y en la misma sesión aislada de EKS.

~~~powershell
$ebs = (Invoke-Kube get pv -o json | ConvertFrom-Json).items |
    Where-Object { $_.spec.storageClassName -eq 'order-manager-gp3' } |
    ForEach-Object { $_.spec.csi.volumeHandle }

helm uninstall alloy --namespace monitoring --kube-context $Context
if ($LASTEXITCODE -ne 0) { throw 'Falló el retiro de Alloy.' }
Invoke-Kube delete namespace order-manager monitoring --wait=true --timeout=5m
Invoke-Kube delete nodepool order-manager --wait=true --timeout=5m
Invoke-Kube get nodeclaims,nodes
# Continuar cuando se hayan retirado los NodeClaims del pool.
Invoke-Kube delete nodeclass order-manager --wait=true --timeout=5m
Invoke-Aws eks delete-cluster --name $Cluster --query cluster.status --output text
Invoke-Aws eks wait cluster-deleted --name $Cluster
Invoke-Aws eks list-clusters --query clusters --output json
~~~

Para cada EBS registrado, confirmar su pertenencia, estado disponible y decisión de respaldo. La política Retain deja esos volúmenes sujetos a cobro hasta su eliminación. Ejecutar la eliminación por ID con autorización expresa. Eliminar solo los snapshots, si existen, y la imagen y el repositorio de esta ejecución cuando ya no hagan falta. Usar la visibilidad de recursos administrados al revisar el inventario de Auto Mode.

~~~powershell
# Sustituir y ejecutar individualmente cada operación aprobada.
Invoke-Aws ec2 describe-volumes --include-managed-resources --volume-ids $VolumeId
Invoke-Aws ec2 delete-volume --volume-id $VolumeId
Invoke-Aws ecr batch-delete-image --repository-name $Repository --image-ids "imageDigest=$Digest"
Invoke-Aws ecr delete-repository --repository-name $Repository
~~~

Verificar que no queden instancias administradas, EBS, snapshots, interfaces ni IPv4 facturables de la evaluación. La VPC, las subredes, los roles del laboratorio y los entornos locales se conservan.
