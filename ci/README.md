# Evidencia de CI/CD y trazabilidad · EP3

## Controles del pipeline

1. **Build, Test & Security Analysis** compila con Java 17, ejecuta Maven y genera JaCoCo HTML y XML. Comprueba el umbral de líneas del proyecto completo, escanea con Gitleaks el árbol exacto que se publicaría y espera el Quality Gate de SonarCloud. El análisis usa Java 21 y requiere `SONAR_TOKEN`.
2. **Container Build, Scan, Simulated Deploy & Verification** depende del éxito del primer job. Construye la imagen de la API y escanea su archivo Docker con Trivy `0.74.0` fijado por digest. Exporta un reporte de vulnerabilidades altas y críticas. Bloquea toda vulnerabilidad crítica detectada, tenga parche disponible o no. Las altas quedan en el informe. Una segunda invocación bloquea secretos altos o críticos en la imagen y descarta la salida del hallazgo. Gitleaks `v8.30.1` bloquea hallazgos en el contenido publicable y redacta su salida. El alcance de Gitleaks es el snapshot, por lo que sigue pendiente la remediación de credenciales históricas. El flujo Trivy cubre la imagen de Order Manager. El proxy ejecuta sus pruebas Go al compilar. Las imágenes externas de observabilidad requieren su propio proceso de actualización y revisión.
3. Tras esos controles, Compose arranca en el runner con credenciales efímeras. La espera de Actuator comprueba también PostgreSQL. Los smoke tests crean, consultan, confirman y listan un pedido sintético. El artefacto distribuible `order-manager-jar` se extrae de la imagen escaneada después de las pruebas HTTP. Los informes de fallos pueden publicarse como evidencia. El workflow no despliega EKS ni publica una imagen en ECR.

Los gates obligatorios usan los códigos de salida de las herramientas. Ante cualquier error anterior a Compose, GitHub omite sus pasos de arranque y verificación. Los pasos que resumen o publican diagnósticos después de un fallo no despliegan. La limpieza actúa únicamente si se intentó levantar el proyecto efímero.

CI aplica `.github/compose.ci.yml` sobre Compose. La API usa `order-manager:<GITHUB_SHA>` con `pull_policy: never`. El workflow guarda por ID el archivo que escanea Trivy y compara ese ID con el del contenedor de la API antes de comprobar salud y endpoints. El JAR se extrae por ID. El artefacto `order-manager-jar` incluye `image-provenance.json`, con SHA del run, etiqueta, ambos IDs y SHA-256 del JAR. Una diferencia de IDs bloquea los artefactos de éxito.

La prueba local construyó la imagen del árbol de trabajo con una etiqueta temporal asociada al SHA base. Usó el override de CI y un Compose de prueba con nombres y puerto independientes y PostgreSQL 16 sobre almacenamiento temporal. Trivy obtuvo cero altos y críticos, el ID del archivo guardado coincidió con el ID del contenedor y el JAR extraído tuvo el mismo SHA-256 que el JAR dentro del contenedor. PostgreSQL reportó `UP`. La comparación con un ID distinto devolvió código 1. La evidencia local está en `target/ep3-publication/image-provenance.json`. La prueba deja pendiente la ejecución de esta cadena en GitHub Actions.

`ci/gitleaks.toml` conserva las reglas predeterminadas y permite el valor exacto del identificador público de SonarCloud en `sonar-project.properties`. Cualquier otro valor sigue sujeto a las reglas.

## Cobertura

El mínimo aprobado es **75 % por líneas** del proyecto completo. El POM fija el umbral y lo aplica en `mvn verify`. Las rutas `target/site/jacoco/index.html` y `target/site/jacoco/jacoco.xml` se incluyen en `test-and-coverage-reports` cuando el workflow las genera.

~~~powershell
mvn -B clean verify
~~~

Para la prueba negativa, cambia el mínimo a `1.00` únicamente en el POM de una copia aislada y ejecuta `mvn -B jacoco:check@coverage-gate` sobre sus datos JaCoCo. Comprueba que el error corresponda a la regla por líneas y que `$LASTEXITCODE` sea 1.

## Configuración de GitHub

1. En SonarCloud, confirma la organización `mkbenja9`, el proyecto `MKbenjA9_Evaluaci-n2Devops`, su vínculo con GitHub y la rama `main`. En **Administration → Analysis Method**, selecciona el análisis de CI y desactiva el análisis automático si sigue activo. En **My Account → Security**, genera un token de un usuario con permiso **Execute Analysis** sobre el proyecto. Confirma el Quality Gate asignado. La ruta XML que importa Maven es `target/site/jacoco/jacoco.xml`.
2. Abre **Settings → Secrets and variables → Actions → Secrets → New repository secret**. Guarda el token como `SONAR_TOKEN`.
3. GitHub Actions crea `GITHUB_TOKEN` automáticamente. El workflow declara `contents: read`. El umbral vive en Maven y el workflow genera credenciales efímeras para la ejecución de Compose. La pestaña **Variables** puede quedar vacía.
4. Después de una ejecución autorizada, configura en **Settings → Rules → Rulesets** la protección de `main`. Exige un PR y los dos checks de jobs después de que GitHub los registre. Consulta la sección de protección de ramas para sus nombres y criterios.

El pipeline compila y ejecuta pruebas con Java 17, inicia el scanner Maven con Java 21 y espera el Quality Gate de SonarCloud. La revisión de la contraseña histórica y el procedimiento autorizado de recuperación y rotación están en la [guía de PostgreSQL](rotacion-postgresql.md).

## Mediciones y Grafana

Consulta la [evidencia remota de la EP3](evidencias-ep3-remotas.md) para el run #38, sus digests publicados, las capturas y el procedimiento de importación aislada.

| Medición | Inicio y fin | Evidencia |
| --- | --- | --- |
| Compilación Maven | Inicio y fin de `mvn clean compile`, en segundos de pared | `compile_seconds` |
| Despliegue en CI | Desde antes de `docker compose up -d --no-build` hasta que pasan Actuator y el smoke test HTTP. Puede incluir descarga de imágenes | `deploy_seconds`, con reloj monotónico |
| Duración completa del pipeline | Desde `startedAt` hasta el último `completedAt` de los jobs al terminar la ejecución. Incluye esperas entre jobs y limpieza | Metadatos del run de GitHub. Se obtiene una vez concluido |

`ci-observability/ci-metrics.json` incluye cobertura JaCoCo, tiempos medidos, SHA, repositorio, ID, intento y fecha UTC. Solo se genera tras un despliegue Compose y smoke test exitosos. El tiempo corresponde al entorno efímero de GitHub Actions. EKS se valida mediante su guía de despliegue y sus evidencias separadas.

El runner hospedado entrega el artefacto. Un operador lo descarga e importa por un canal local a Loki. Grafana consulta Loki desde ambos entornos. El dashboard mantiene los seis paneles Prometheus y muestra los últimos valores de CI importados dentro de siete días. Sin datos en esa ventana, el dashboard queda sin muestra. Importa las ejecuciones recientes en orden cronológico para evitar los límites de Loki sobre registros fuera de orden.

Compose y Kubernetes usan el mismo JSON en `k8s/observability/grafana/order-manager.json`. Conserva el JSON de seis paneles bajo `monitoring/grafana/dashboards/` mientras exista un despliegue anterior que monte esa carpeta. Adoptar el dashboard de ocho paneles requiere aplicar el nuevo montaje de Compose o el ConfigMap de Kubernetes en un despliegue autorizado.

~~~powershell
$RunId = Read-Host 'ID de un run exitoso del repositorio'
$Run = gh run view $RunId --json startedAt,jobs,status,conclusion | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $Run.status -ne 'completed' -or $Run.conclusion -ne 'success') {
    throw 'Se requiere una ejecución exitosa.'
}
$LastJob = $Run.jobs.completedAt | Where-Object { $_ } | Sort-Object | Select-Object -Last 1
([DateTimeOffset]$LastJob - [DateTimeOffset]$Run.startedAt).TotalSeconds
$Evidence = Join-Path $env:TEMP "order-manager-ci-$RunId"
gh run download $RunId --name ci-observability --dir $Evidence
if ($LASTEXITCODE -ne 0) { throw 'Falló la descarga del artefacto.' }
$Artifact = Join-Path $Evidence 'ci-metrics.json'

# Compose actualizado. Grafana alcanza Loki por la red interna de contenedores.
./ci/Import-CiMetrics.ps1 -Artifact $Artifact -Compose
~~~

Para kind o EKS, abre un port-forward temporal de Loki en otra terminal. Usa el contexto exacto del entorno autorizado.

~~~powershell
$Context = 'kind-order-manager-lab'
kubectl --context $Context -n monitoring port-forward --address 127.0.0.1 svc/loki 13100:3100
~~~

Importa con `./ci/Import-CiMetrics.ps1 -Artifact $Artifact -LokiPort 13100`, revisa ambos paneles en Grafana y termina el port-forward. Mantén Loki sin publicación externa.

## Pruebas y evidencias

- **Positiva local.** Ejecuta `verify` con Java 17 y comprueba ambos informes y el gate aprobado del 75 %. Valida también el JSON del dashboard de ocho paneles.
- **Negativa de pruebas.** En una copia temporal, añade un método JUnit con `Assertions.fail("negative gate test")` y ejecuta solo esa clase con `mvn -B -Dtest=LocalGateNegativeTest test`. Comprueba que Surefire registra un fallo y devuelve código distinto de cero. La copia temporal debe quedar fuera de Git.
- **Negativa de cobertura.** Usa `1.00` con el informe actual, comprueba el error de la regla y conserva el log. El umbral aprobado del repositorio debe permanecer intacto.
- **Política de vulnerabilidades.** Guarda el JSON de prueba de abajo fuera del repositorio como `report.json`. Ejecuta con la misma imagen Trivy fijada en el workflow y con el directorio de prueba montado en `/scan:ro`. La ejecución debe terminar con código 1. Cambia solo `Severity` a `HIGH` y espera código 0. El fixture describe un hallazgo sintético sin parche y no instala software vulnerable.

El escaneo inicial se reprodujo con **36 hallazgos altos y 9 críticos**. Tras la remediación con Boot 3.5 quedaron dos críticos. Boot 4.0.10 obtuvo **0 altos y 0 críticos** en la comparación con ambas bases de Trivy congeladas. Consulta el [informe de remediación inicial](remediacion-ep3.md) y el [informe de migración](migracion-spring-boot-4.md).

~~~json
{
  "SchemaVersion": 2,
  "ArtifactName": "isolated-fixture",
  "ArtifactType": "container_image",
  "Results": [{
    "Target": "synthetic",
    "Class": "lang-pkgs",
    "Type": "jar",
    "Vulnerabilities": [{
      "VulnerabilityID": "TEST-SYNTHETIC",
      "PkgName": "synthetic-fixture",
      "InstalledVersion": "0.0.0",
      "FixedVersion": "",
      "Severity": "CRITICAL",
      "Status": "will_not_fix"
    }]
  }]
}
~~~

~~~text
trivy convert --format table --severity CRITICAL --exit-code 1 /scan/report.json
~~~

Cuando se autorice publicar, ejecuta el workflow desde un PR hacia `main` con SonarCloud configurado. Si el equipo usa `workflow_dispatch`, GitHub requiere que el workflow esté registrado en la rama predeterminada. Obtén el ID desde Actions y usa `gh run watch <ID> --exit-status`. Consulta el detalle con `gh run view <ID>`. Guarda URL, SHA, intento, Quality Gate, informes Maven y Trivy, resumen de tiempos y capturas del dashboard después de importar el artefacto. Para evidencia negativa remota, usa un PR controlado que falle una aserción con datos sintéticos. Comprueba en el gráfico que el job de contenedores quede omitido. Para Trivy, usa el fixture en un workflow aislado con un paso posterior que solo imprima un marcador. Verifica que el paso quede omitido al obtener un código 1. Conserva las evidencias de fallos y retira los fixtures de la rama de evidencia según autorización.

## Protección de ramas recomendada

En `main` y en cualquier otra rama protegida que ejecute este workflow, exigir pull request, aprobación independiente y los dos checks de jobs. Tras el primer run, seleccionar los nombres exactos reportados por GitHub Actions. Requerir que estén actualizados con la rama base, invalidar aprobaciones ante cambios nuevos y restringir bypass, pushes directos, force-push y borrado. Revisar cualquier cambio en el workflow, el umbral o reglas de escaneo antes del merge. Los PR sin acceso a `SONAR_TOKEN` necesitan un flujo aprobado y seguro. Nunca conceder ese secreto a código de forks sin revisar. Esto documenta prácticas de revisión y mínimo privilegio.

## Matriz de trazabilidad EP3

| Indicador | Implementación y archivos | Evidencia disponible | Evidencia pendiente |
| --- | --- | --- | --- |
| **IE1 · 20 %** | Actuator y Micrometer, Prometheus, Loki, Alloy y Grafana | Health, probes y scrape reales en Boot 4. Seis consultas PromQL pasaron. Alloy y Loki verificaron los eventos 404 y 500 sanitizados | Capturas finales en un entorno autorizado |
| **IE2 · 20 %** | EKS estándar, Kustomize, Helm y aprovisionamiento de observabilidad | Render de los tres overlays aprobado, sustitución de registro y digest EKS probada con datos sintéticos y migración sobre PostgreSQL 16 aislado verificada. Nodo, pods y PVC tienen evidencia del despliegue previo | Validación de Boot 4 en Kubernetes cuando se autorice |
| **IE3 · 10 %** | JaCoCo, reloj de CI, artefacto `ci-observability`, importador y Grafana | Validado funcionalmente. Run #38: 85,0515 % de líneas, compilación 15 s, despliegue 46,54 s y pipeline 270 s. Evento real importado, dos consultas LogQL verificadas y seis consultas PromQL verificadas con tráfico local aislado | Capturar el dashboard en los rangos documentados |
| **IE4 · 10 %** | Esta guía, documentación de Kubernetes e informes EP3 | Migración, comparación de CVE, trazabilidad de imagen, procedimiento de rotación y resultados de los runs #38 y #39 documentados | Completar capturas y archivar logs y ZIP originales |
| **IE5 · 20 %** | Maven, JaCoCo, Gitleaks, SonarCloud, Trivy y checks de rama | Remoto: cinco ZIP con hash verificado, 38 pruebas aprobadas, 85,0515 % de líneas, cero vulnerabilidades altas/críticas y tres checks aprobados. Hash del JAR e IDs de procedencia verificados en los ZIP | Reconciliar el ID de Trivy con el de Docker, obtener logs, capturar SonarCloud y verificar protección efectiva de `main` tras autorización |
| **IE6 · 20 %** | Códigos de salida obligatorios y dependencia entre jobs | Validado funcionalmente. Local: Maven salió con 1. Remoto: PR #14 en borrador, run #39 con Maven en `failure` y despliegue en `skipped` sin pasos | Descargar el ZIP de diagnóstico y los logs originales, verificar el hash y guardar capturas |

En el EKS del laboratorio, los cuatro PVC de PostgreSQL, Prometheus, Grafana y Loki usan directorios del disco raíz del nodo con afinidad local. Ante reemplazo o terminación del nodo pueden quedar inaccesibles y los datos se pueden perder. `Retain` se aplica al PV y el disco raíz sigue el ciclo de vida de EC2. Una restauración en otro nodo requiere respaldo externo. Los indicadores entregados no exigen EBS CSI explícitamente. Consulta el [procedimiento EKS y sus limitaciones](../k8s/overlays/eks-local-storage/README.md).

El diagnóstico de solo lectura confirmó que Auto Scaling terminó el nodo original tras su detención. El reemplazo arrancó con un disco nuevo desde la AMI base y CloudTrail registró que una SCP denegó `ec2:DescribeInstances` durante el arranque de `nodeadm`. Kubernetes no tenía nodos registrados. Los cuatro PV seguían asociados a los PVC y al hostname original. La existencia de una copia recuperable del disco original queda sin confirmar. El Secret de PostgreSQL difiere de la contraseña histórica y la validación TCP de ambas credenciales en EKS queda pendiente hasta recuperar una base operativa. La recuperación de EKS se gestiona por separado del CI de GitHub, cuyo despliegue simulado se ejecuta en el runner.
