# Order Manager API en Kubernetes local

La práctica local usa el clúster kind order-manager-lab y el contexto kind-order-manager-lab. Consulta la [guía de EKS estándar](overlays/eks-local-storage/README.md) para reproducir el despliegue en AWS con almacenamiento local. Los contenedores y volúmenes de Compose pertenecen a un entorno independiente.

## Arquitectura

- El namespace order-manager contiene la API en un Deployment y PostgreSQL en un StatefulSet. La API usa el Service headless postgres y arranca con el perfil docker. Readiness comprueba también PostgreSQL. Liveness verifica el estado de la aplicación sin depender de PostgreSQL.
- El namespace monitoring contiene Prometheus, Grafana, Loki y Alloy. Los Services son internos. Prometheus recolecta en el Service de la API. Grafana presenta seis métricas operativas y dos métricas de CI obtenidas del artefacto importado a Loki. Consulta la [guía de importación](../ci/README.md#mediciones-y-grafana).
- Alloy usa la API de Kubernetes y una cuenta de servicio con acceso a pods y pods/log en order-manager. Filtra por etiqueta y nombre de contenedor. Mantiene application, service y container. Envía el nivel y una lista cerrada de fragmentos, con [message withheld] para el texto restante.
- PostgreSQL, Prometheus, Loki y Grafana usan PVC separados. En kind los PVC residen en el nodo mediante la clase standard. La recreación de un pod conserva el PVC. Eliminar el clúster puede eliminar los datos locales. Loki conserva logs durante siete días y Prometheus conserva hasta 48 horas, sujeto a su límite de almacenamiento.
- Los Secrets postgres-auth y grafana-auth se generan en la API de Kubernetes desde memoria. El script es idempotente y conserva valores existentes.

## Requisitos e instalación

Usar Docker Desktop con contenedores Linux, kubectl 1.34 o 1.35, kind 0.31.0 y Helm 4.3.2. Si faltan kind o Helm, descargar sus binarios oficiales y comprobar el SHA256. Se pueden descomprimir en un directorio temporal. Los comandos a continuación suponen que sus ejecutables están en PATH. Abrir PowerShell en la raíz del repositorio.

~~~powershell
$Context = 'kind-order-manager-lab'
$env:KUBECONFIG = Join-Path $env:TEMP 'order-manager-lab.kubeconfig'
$Node = 'kindest/node:v1.35.0@sha256:452d707d4862f52530247495d180205e029056831160e22870e37e3f6c1ac31f'

kind version
kubectl --context $Context version --client
helm version
docker build --platform linux/amd64 -t order-manager:k8s-local .
kind create cluster --name order-manager-lab --image $Node --kubeconfig $env:KUBECONFIG --wait 120s
kind load docker-image order-manager:k8s-local --name order-manager-lab
kubectl --context $Context get nodes,storageclass
~~~

Si el clúster ya existe, reutilizar su kubeconfig aislado y omitir la creación. En la ejecución de validación se usó el kubeconfig en %TEMP%\order-manager-k8s-tools\order-manager-lab.kubeconfig. Revisar el código de salida de cada comando antes de continuar.

## Validación y despliegue

~~~powershell
$Chart = @('alloy','alloy','--repo','https://grafana.github.io/helm-charts','--version','1.16.0','--namespace','monitoring','-f','k8s/observability/alloy-values.yaml')
docker run --rm --mount "type=bind,source=$($PWD.Path),target=/build" --workdir /build maven:3.9.9-eclipse-temurin-17-alpine mvn -B -ntp test

$Config = (Resolve-Path k8s/observability).Path
docker run --rm --mount "type=bind,source=$Config,target=/config,readonly" grafana/loki:3.7.8 '-config.file=/config/loki.yml' '-verify-config'
docker run --rm --mount "type=bind,source=$Config,target=/config,readonly" grafana/alloy:v1.22.0 validate /config/config.alloy
docker run --rm --entrypoint /bin/promtool --mount "type=bind,source=$Config,target=/config,readonly" prom/prometheus:v3.16.0 check config /config/prometheus.yml

kubectl --context $Context kustomize k8s/overlays/local
kubectl --context $Context kustomize k8s/overlays/eks
$Alloy = helm template @Chart --kube-version 1.35.0
kubectl --context $Context apply --dry-run=server -f k8s/base/namespaces.yaml
kubectl --context $Context apply -f k8s/base/namespaces.yaml
kubectl --context $Context apply --dry-run=server -k k8s/overlays/local
$Alloy | kubectl --context $Context apply --dry-run=server -f -

powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File k8s/scripts/New-LabSecrets.ps1
kubectl --context $Context apply -f k8s/base/alloy-rbac.yaml
kubectl --context $Context auth can-i list pods --as=system:serviceaccount:monitoring:alloy -n order-manager
kubectl --context $Context auth can-i get pods --subresource=log --as=system:serviceaccount:monitoring:alloy -n order-manager
kubectl --context $Context auth can-i get secrets --as=system:serviceaccount:monitoring:alloy -n order-manager
kubectl --context $Context auth can-i get pods --subresource=log --as=system:serviceaccount:monitoring:alloy -n monitoring

kubectl --context $Context apply -f k8s/base/postgres.yaml
kubectl --context $Context -n order-manager rollout status sts/postgres --timeout=180s
kubectl --context $Context apply -k k8s/overlays/local
helm upgrade --install @Chart --kube-context $Context
kubectl --context $Context -n order-manager rollout status deploy/order-manager --timeout=180s
foreach ($service in 'prometheus','grafana','loki','alloy') {
    kubectl --context $Context -n monitoring rollout status "deploy/$service" --timeout=180s
}
kubectl --context $Context get pods,deploy,sts,svc,pvc -A
~~~

Los dos primeros controles RBAC deben devolver yes y los dos últimos, no. Para cambios posteriores en ConfigMaps, reiniciar el Deployment consumidor. Alloy usa el chart sin recargador auxiliar.

## Verificación y capturas

~~~powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File k8s/scripts/Test-Lab.ps1 -CheckPersistence -KeepPortForwards
~~~

El script valida los endpoints de Actuator, un 404 controlado, el target y el histograma HTTP de Prometheus, las dos fuentes de Grafana y registros de ambos servicios en Loki. Con CheckPersistence crea un pedido sintético y un dashboard marcador, reemplaza los pods con estado y verifica que se conservan el pedido, el marcador, una muestra histórica, un registro histórico y las cuatro identidades PVC/PV. Los marcadores permanecen como evidencia. KeepPortForwards deja los tres accesos en funcionamiento. Para repetir la prueba, cerrar primero sus port-forwards previos.

Si se prefieren terminales separadas, definir KUBECONFIG y Context en cada una y ejecutar un comando por terminal.

~~~powershell
kubectl --context $Context -n order-manager port-forward --address 127.0.0.1 svc/order-manager 18098:8098
kubectl --context $Context -n monitoring port-forward --address 127.0.0.1 svc/grafana 13000:3000
kubectl --context $Context -n monitoring port-forward --address 127.0.0.1 svc/prometheus 19090:9090
~~~

- [API y Actuator](http://127.0.0.1:18098/actuator/health)
- [Target de Prometheus](http://127.0.0.1:19090/targets)
- [Dashboard Order Manager API](http://127.0.0.1:13000/d/order-manager-api)
- [Grafana Explore](http://127.0.0.1:13000/explore)

Para entrar a Grafana se usa admin. Un operador autorizado puede copiar la contraseña al portapapeles sin imprimirla en PowerShell.

~~~powershell
$Encoded = kubectl --context $Context -n monitoring get secret grafana-auth -o 'jsonpath={.data.password}'
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Encoded)) | Set-Clipboard
Remove-Variable Encoded
# Después de iniciar sesión, limpiar el portapapeles si ya no se necesita.
Set-Clipboard -Value ''
~~~

En Explore, seleccionar Loki y usar uno de estos selectores.

~~~logql
{application="order-manager"}
{application="order-manager",service="db",container="postgres"}
{application="order-manager",service="app",container="api"} |= "status=404"
~~~

## Diagnóstico y preparación de EKS

- Si la API no está Ready, comprobar primero PostgreSQL y el Secret. En un despliegue simultáneo, el DNS del Service headless puede quedar sin endpoints hasta que PostgreSQL esté Ready. Un PVC que permanece Pending requiere revisar la clase de almacenamiento, el provisionador local y los eventos del pod.
- Si Loki responde temporalmente 503, comprobar el estado de sus probes y esperar a que termine la inicialización. Si una consulta devuelve datos vacíos, comprobar el rango temporal y los permisos de Alloy.
- Si Windows rechaza un script local, ejecutar el comando anterior con RemoteSigned limitado a ese proceso. Si un port-forward termina tras sustituir un pod, volver a iniciarlo.
- La [guía de EKS Auto Mode](aws/README.md) describe los requisitos IAM pendientes, la publicación en ECR, la configuración de cómputo y el retiro controlado de recursos.
- El overlay EKS usa el provisionador integrado de Auto Mode, con gp3 cifrado y política Retain. Las plantillas anteriores de grupo de nodos administrado y EBS CSI se conservan como referencia para una alternativa que requiere aprobación separada.
