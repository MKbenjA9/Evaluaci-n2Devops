# Evidencias remotas de la EP3

## Ejecución positiva

El [PR #13](https://github.com/MKbenjA9/Evaluaci-n2Devops/pull/13) sigue abierto hacia `main`. GitHub confirmó un commit, 70 archivos modificados y el SHA de cabeza `2e3123ed72a470a130eb5dbda3c2139a3fa37927`. La [ejecución #38](https://github.com/MKbenjA9/Evaluaci-n2Devops/actions/runs/46017294434), ID `46017294434`, intento 1, se creó e inició el 27 de noviembre de 2026 a las 14:35:26 UTC. El último job terminó a las 14:39:56 UTC. Duración total de 270 s.

| Check exacto de GitHub | Emisor | Resultado |
| --- | --- | --- |
| Build, Test & Security Analysis | GitHub Actions | success, 87 s de job |
| Container Build, Scan, Simulated Deploy & Verification | GitHub Actions | success, 179 s de job |
| SonarCloud Code Analysis | SonarQube Cloud | success |

La API de Actions confirma el éxito de Maven, registro JaCoCo, Gitleaks sobre el árbol publicable, SAST, gate Trivy de vulnerabilidades críticas, escaneo de secretos altos/críticos de la imagen, Compose, comparación de IDs, salud de PostgreSQL, smoke HTTP y extracción del JAR. El umbral de JaCoCo en el POM es 75 %. El gate de vulnerabilidades bloquea las críticas y el JSON incluye altas y críticas. Los IDs y la comprobación del JAR se detallan en Artefactos.

SonarCloud reportado para el PR por el equipo: Quality Gate PASSED, 95,7 % de cobertura nueva, 0,0 % de duplicación nueva, cero issues nuevos y cero hotspots. GitHub confirma el check y el éxito del paso con espera del Quality Gate. Las cifras del panel siguen pendientes de captura directa. [Panel de SonarCloud](https://sonarcloud.io/dashboard?id=MKbenjA9_Evaluaci-n2Devops&pullRequest=13)

Como antecedente local, Spring Boot 4.0.10, Spring Framework 7.0.11, Java 17 y PostgreSQL 16, 38 pruebas aprobadas sin fallos ni omitidas, 85,05 % de líneas, 63,33 % de ramas, Gitleaks aprobado y cero vulnerabilidades altas/críticas en Trivy. Los conteos remotos se verifican con los ZIP y logs.

## Artefactos

Los cinco ZIP originales se localizaron en `Downloads/Evidencias-EP3`. Los cinco SHA-256 calculados coincidieron con los digests de la tabla, cotejados con la API de GitHub. Los originales se conservaron y la extracción quedó bajo `target/ep3-ie3-run38/extracted`, ignorado por Git. El ZIP de logs del #38 no estaba en la carpeta. La descarga sin autenticar devolvió HTTP 403 en la comprobación anterior.

| ZIP | ID | SHA-256 publicado y verificado | Resultado |
| --- | --- | --- | --- |
| ci-observability | 15206408805 | `b0f65bd6179cee932c0369ecee65fd821162263d95a1f7f9dab55fb0679d0adc` | Run 46017294434, intento 1, `compose_smoke_success`, 85,0515 %, compilación 15 s, despliegue 46,54 s |
| coverage-metrics | 15206825580 | `6d36e97631ce0a4277c3b8cbf8e5ab2e884b2c306428d1cc4f8501a3333b8977` | 165 líneas cubiertas, 29 omitidas y 15 s de compilación. Coincide con observabilidad y con los contadores JaCoCo |
| order-manager-jar | 15206542255 | `2b993685b5f865716b8210e576e06ae47a18bcfcafa4658ab88b624b69abcd5a` | JAR ejecutable y `image-provenance.json` presentes. Hash del JAR y comparación de IDs de procedencia verificados |
| test-and-coverage-reports | 15205839388 | `20af7ebcbd9cfaf39f0ae41afe1b62dd3faa5d5a3a2583ddd8840a06c8872762` | Surefire: 38 pruebas, cero fallos, errores y omitidas. JaCoCo: líneas 165/194 (85,0515 %, supera 75 %), ramas 38/60 (63,33 %) |
| trivy-vulnerabilities | 15206726113 | `77623af14c6e7dfd046c65282004b84ad0eb0a61b005da9abce34b66b134d86f` | Cero vulnerabilidades HIGH y CRITICAL en las dos entradas del reporte (Alpine 3.24.4 y Java). El JSON está limitado a esas severidades |

El SHA ejecutado `e17b66902bb49d3166c625ee24951a4693353928` coincide en los dos JSON que lo registran. GitHub confirmó que sus padres son la base de `main` y la cabeza aprobada del PR #13. El SHA-256 calculado del JAR es `cde6ef06f574b3db5d38fb48b43381d2ab48d26c368763df98e5dd9f251a910e` y coincide con `jar_sha256`. `scanned_image_id` y `running_image_id` coinciden en `sha256:39bec32a98c8ac9541606771d179a69cfd11326a7f85a4ba732b7b8aa357881a`. Trivy declara un `Metadata.ImageID` distinto, `sha256:da725dc243c626648c2e586917681afbec39ba80499057c23948194897566f9f`. Queda pendiente reconciliar ambos identificadores con el archivo Docker original o evidencia equivalente. El paso de Actions que compara los IDs de Docker aprobó. Los logs originales siguen pendientes para revisar directamente los pasos de escaneo de secretos.

## IE3 · Grafana

El importador existente cargó en Loki el evento real `compose_smoke_success` del run #38, intento 1, registrado a las **14:39:35,881865 UTC**. Loki lo recuperó mediante el datasource configurado en Grafana. El tiempo de despliegue de **46,54 s** y el tiempo de compilación de **15 s** provienen del JSON. Los **270 s** corresponden al pipeline completo según Actions.

Las ocho consultas se ejecutaron con las expresiones del dashboard provisionado. Las seis de aplicación se midieron a las 15:43:55 UTC sobre el JAR remoto ejecutado localmente con Java 17 y PostgreSQL aislado. Se generaron 36 respuestas HTTP 200 y 36 respuestas HTTP 404 con peticiones GET. Prometheus informó `up` sin error de scrape y Actuator informó aplicación y PostgreSQL en `UP`.

| Panel | Consulta | Resultado |
| --- | --- | --- |
| CPU del proceso | `100 * process_cpu_usage{job="order-manager"}` | 6,3492 % |
| Memoria heap usada | `sum(jvm_memory_used_bytes{job="order-manager",area="heap"})` | 33.740.560 bytes |
| Disponibilidad de recolección | `up{job="order-manager"}` | 1 |
| Peticiones HTTP | `sum(rate(http_server_requests_seconds_count{job="order-manager",uri=~"/api/orders(/.*)?"}[5m]))` | 0,256738 solicitudes/s |
| Errores HTTP | `sum by (status) (rate(http_server_requests_seconds_count{job="order-manager",uri=~"/api/orders(/.*)?",status=~"[45].."}[5m]))` | 0,128369 solicitudes/s con estado 404 |
| Latencia HTTP p95 | `1000 * histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket{job="order-manager",uri=~"/api/orders(/.*)?"}[5m])))` | 12,118 ms |
| Cobertura de líneas en CI | `last_over_time({application="order-manager",source="github-actions",event="compose_smoke_success"} &#124; json value="coverage_percent" &#124; unwrap value &#124; __error__="" [7d])` | 85,0515 % |
| Tiempo de despliegue en CI | `last_over_time({application="order-manager",source="github-actions",event="compose_smoke_success"} &#124; json value="deploy_seconds" &#124; unwrap value &#124; __error__="" [7d])` | 46,54 s |

Las respuestas se guardaron en `target/ep3-ie3-run38` como `promql.json`, `logql.json`, `loki-event.json`, `prometheus-targets.json` y `traffic.json`. El proyecto `ep3-run38-evidence` quedó activo para las capturas. Solo añadió cinco contenedores, cuatro volúmenes y dos redes con prefijo propio. El inventario de recursos previos y Kind coincidió antes y después.

- [Grafana · evento #38, 14:35–14:45 UTC](http://127.0.0.1:13000/d/order-manager-api/order-manager-api?from=1795790100000&to=1795790700000&timezone=utc). Captura los dos paneles de CI.
- [Grafana · ventana de tráfico local](http://127.0.0.1:13000/d/order-manager-api/order-manager-api?from=1795793935638&to=1795794355638&timezone=utc). Captura los seis paneles de aplicación. Los paneles CI conservan el último valor del run dentro de la ventana de siete días.
- [Targets de Prometheus](http://127.0.0.1:19090/targets) y [Actuator Health](http://127.0.0.1:18098/actuator/health). Captura el scrape en `UP` y los estados de salud.

Para reproducir la validación, utiliza el override generado en `target/ep3-ie3-run38/compose.run38.yml`. Monta el JAR verificado en solo lectura y usa el JRE local. El ejemplo siguiente usa una compilación local con etiqueta propia como alternativa para validar el scrape. Los volúmenes se crean con el prefijo del proyecto dedicado.

```yaml
services:
  db:
    container_name: !reset null
    ports: !reset []
  app:
    container_name: !reset null
    image: order-manager:ep3-run38-evidence
    ports: !override ["127.0.0.1:18098:8098"]
  prometheus:
    ports: !override ["127.0.0.1:19090:9090"]
  grafana:
    ports: !override ["127.0.0.1:13000:3000"]
```

Desde la raíz, define `$Evidence` como la carpeta externa y `$Artifact` como la ruta del `ci-metrics.json` original extraído. En una sesión PowerShell nueva:

```powershell
$env:COMPOSE_DISABLE_ENV_FILE = '1'
$env:COMPOSE_PROJECT_NAME = 'ep3-run38-evidence'
$env:COMPOSE_FILE = "$(Join-Path $PWD 'docker-compose.yml');$(Join-Path $Evidence 'compose.run38.yml')"
$env:DB_USER = 'order_evidence'
$env:DB_PASSWORD = [guid]::NewGuid().ToString('N')
$env:GRAFANA_ADMIN_PASSWORD = [Net.NetworkCredential]::new('', (Read-Host 'Contraseña efímera para Grafana' -AsSecureString)).Password
docker compose config --quiet
docker compose config --volumes
docker compose up -d --build db app prometheus loki grafana
docker compose ps
./ci/Import-CiMetrics.ps1 -Artifact $Artifact -Compose
```

Comprueba los puertos y que el nombre de proyecto esté libre antes de iniciarlo. El importador admite siete días desde la fecha del evento. Si vence esa ventana, conserva el timestamp real y documenta la limitación antes de adaptar el entorno aislado.

Capturas a obtener:

1. **Actions → Summary**, con número, duración, los jobs y la lista de artefactos. Abre los jobs y captura Maven, Gitleaks, Trivy, escaneo de secretos, comparación de IDs, healthcheck y smoke HTTP. [Ejecución #38](https://github.com/MKbenjA9/Evaluaci-n2Devops/actions/runs/46017294434)
2. **PR → Checks** y el **Overview del PR en SonarCloud**. Incluye los tres checks, Quality Gate y métricas de código nuevo. [Checks del PR](https://github.com/MKbenjA9/Evaluaci-n2Devops/pull/13/checks) · [SonarCloud](https://sonarcloud.io/dashboard?id=MKbenjA9_Evaluaci-n2Devops&pullRequest=13)
3. **Prometheus → Status → Targets**, en `http://127.0.0.1:19090/targets`, con `order-manager` en UP. En Grafana, abre `http://127.0.0.1:13000/d/order-manager-api`, elige un rango que contenga el timestamp real y captura los ocho paneles. Usa **Inspect → Query** para revisar los errores y contrasta los valores CI con el JSON.
4. **Grafana → Explore → Loki**, con el intervalo del run y `{application="order-manager",source="github-actions",event="compose_smoke_success"} | json | run_id="46017294434"`. Captura ID, intento, fecha, cobertura y tiempos. Las métricas de aplicación en Prometheus que produzca el entorno local solo acreditan que el scrape y las consultas funcionan en ese entorno.
5. **Settings → Branches / Rules → Rulesets**, tras autorización y aplicación. Captura la regla activa y los contextos obligatorios. En la ejecución negativa captura el gráfico, el paso Maven expandido y el job de contenedores en `skipped`.

En Prometheus **Status → Targets** comprueba el endpoint de Actuator y ejecuta las seis expresiones del [dashboard provisionado](../k8s/observability/grafana/order-manager.json) en `http://127.0.0.1:19090/query`. En Loki ejecuta las dos expresiones del mismo JSON. Un panel de errores HTTP sin series puede corresponder a la ausencia de respuestas 4xx/5xx en el rango. Distingue ese caso de un error en **Inspect → Query**.

## IE5 · Protección de main

La API pública reportó `protected: false` para `main` y devolvió listas vacías de reglas efectivas y rulesets visibles. El detalle de protección clásica exige autenticación. Se verificó que el repositorio es público y que `main` es su rama predeterminada. GitHub Free admite protección de ramas para repositorios públicos. En repositorios privados se requiere GitHub Pro, Team, Enterprise Cloud o Enterprise Server. Un administrador o rol con permisos de edición debe configurar la regla. [Documentación de GitHub](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)

1. Tras aprobar la propuesta, abre **Settings → Branches → Add branch protection rule** y escribe `main` en **Branch name pattern**. Si ya existe una regla aplicable, abre **Edit** y verifica sus controles.
2. Activa **Require a pull request before merging**. Si la evaluación permite autoevaluación y no hay segundo revisor, deja sin activar **Require approvals**.
3. Activa **Require status checks to pass before merging** y selecciona los tres checks exactos de la tabla. Asocia los dos jobs a GitHub Actions y el análisis a SonarQube Cloud si el selector permite fijar la app. Deja desactivado inicialmente **Require branches to be up to date before merging**.
4. Deja desactivados **Allow force pushes** y **Allow deletions**. Confirma quién puede editar la regla y activa **Do not allow bypassing the above settings** para que los requisitos se apliquen también a los administradores.
5. Pulsa **Create** o **Save changes**. Vuelve a abrir la regla y comprueba los tres checks y el cuadro de merge del PR #13 sin integrarlo. Si falta un check en el selector, verifica el nombre, la app y que haya una ejecución exitosa reciente antes de guardar.

## IE6 · Bloqueo validado en GitHub Actions

Archivo exacto: `src/test/java/com/example/ordermanager/NegativeGateTest.java`. Una prueba JUnit llama a `fail("EP3 IE6: fallo Maven intencional")`. El fixture se prepara bajo `target/ep3-run38-negative` en una copia del SHA aprobado. El paso de Actions ejecuta `mvn -B verify` y el job de contenedores declara `needs: build-and-test`. El paso de diagnóstico Surefire tiene `!cancelled()` y puede publicar el informe aunque Maven falle. El evento `push` solo escucha `main`, por lo que publicar la rama temporal por sí solo no inicia este workflow.

Validación local en la copia aislada con Maven 3.9.16, JDK 25 y `mvn -o -B verify` con la caché existente. Surefire ejecutó 39 pruebas y registró exactamente el fallo intencional, cero errores y cero omitidas. Maven devolvió 1. El log y el código de salida están en `target/ep3-run38-negative/maven-negative.log` y `target/ep3-run38-negative/exit-code.txt`, ignorados por Git. El runner remoto configura Java 17 y su resultado sigue pendiente.

La API confirma que el [PR #14](https://github.com/MKbenjA9/Evaluaci-n2Devops/pull/14) sigue abierto en borrador, de `test/ep3-negative-gate` hacia `main`. El SHA de cabeza es `a45d97bd42da3f0fdcf534830199ccc5ab76b446` y el commit agrega únicamente el fixture. La [ejecución #39](https://github.com/MKbenjA9/Evaluaci-n2Devops/actions/runs/46023575073), ID `46023575073`, intento 1, evento `pull_request`, concluyó en `failure`. Inició el 27 de noviembre de 2026 a las 15:17:27 UTC y el último job cerró a las 15:18:16 UTC. Duración total calculada con la API de 49 s.

| Job | Run #38 positivo | Run #39 negativo |
| --- | --- | --- |
| Build, Test & Security Analysis | `success`, 87 s | `failure`, 47 s (15:17:29–15:18:16 UTC) |
| Container Build, Scan, Simulated Deploy & Verification | `success`, 179 s | `skipped`, sin pasos ejecutados |

La API confirma el fallo de **Ejecutar Pruebas Automatizadas y Generar Cobertura** y el éxito del paso que publica los reportes. Con el resultado `skipped` del job dependiente y la lista vacía de pasos, **IE6 queda validado funcionalmente**. [Job Maven](https://github.com/MKbenjA9/Evaluaci-n2Devops/actions/runs/46023575073/job/140589101170) · [Job omitido](https://github.com/MKbenjA9/Evaluaci-n2Devops/actions/runs/46023575073/job/140589520306)

El detalle del log confirmado por el equipo registra `mvn -B verify`, 39 pruebas (38 aprobadas, un fallo intencional, cero errores y cero omitidas), `NegativeGateTest.blocksDeploymentWhenMavenFails:10`, mensaje `EP3 IE6: fallo Maven intencional`, `BUILD FAILURE` y código de salida 1. Maven reportó 15,861 s y finalizó a las 15:18:13 UTC. La duración de Maven y el cierre del job corresponden a eventos distintos.

Queda pendiente descargar el log original y el ZIP `test-and-coverage-reports`, ID `15211035650`, con SHA-256 publicado `927a4960fb15b74aec591bbba495afbb342d47424d7e09303b537a5d8b3c0160`. La consulta sin autenticar devolvió HTTP 403 para los logs y 401 para el ZIP. GitHub indicaba vencimiento el 4 de diciembre de 2026 a las 15:18:13 UTC. Con sesión iniciada, descarga el ZIP desde **Summary → Artifacts**, descarga los logs desde el menú de la ejecución y compara el hash antes de extraer. Captura **Summary** con el gráfico de jobs y el paso Maven expandido con el mensaje y la salida 1. Conserva las copias fuera del repositorio.

## Evidencias restantes de IE1–IE5

1. **IE3.** Importación real y ocho consultas verificadas. Guarda las capturas con los dos rangos enlazados arriba.
2. **IE1.** Usa la misma instancia aislada para capturar el endpoint Actuator, el target en UP y los seis paneles de aplicación. Para Loki y Alloy, conserva la evidencia local previa o captura eventos sanitizados en un entorno autorizado. Identifica las capturas de aplicación como locales.
3. **IE5.** Descarga los logs originales del #38, reconcilia los identificadores de imagen de Trivy y Docker y captura SonarCloud. Tras autorización, activa y captura la regla de `main` según el procedimiento anterior.
4. **IE2.** Conserva el render de overlays y las capturas históricas de Kubernetes. La validación actual de Boot 4 en Kubernetes requiere un entorno autorizado. En ese entorno, guarda el resultado de `kubectl get nodes`, el estado de pods y PVC en sus namespaces y una captura de salud de la aplicación. La recuperación de EKS sigue fuera de alcance.
5. **IE4.** Incorpora al expediente los enlaces, reportes y capturas anteriores, con fecha, run y origen de cada evidencia. Conserva ZIP, logs y capturas fuera de Git.

## Estado de recursos

Las consultas inicial y final mostraron los mismos cuatro proyectos Compose activos, los mismos contenedores por estado, los mismos volúmenes y el clúster Kind `order-manager-lab`. La API local de Order Manager figuró en ejecución, PostgreSQL y la pila de observabilidad de este proyecto figuraron detenidos. Se consultó Docker/Kind en solo lectura. EKS queda fuera de alcance. El diagnóstico previo registra cero nodos, denegación SCP de `ec2:DescribeInstances` y riesgo de pérdida de almacenamiento local del nodo original. [Diagnóstico y procedimiento EKS](../k8s/overlays/eks-local-storage/README.md)

La API confirmó que el PR #13 sigue abierto sin merge y que `feature/evaluacion-3` apunta a `2e3123ed72a470a130eb5dbda3c2139a3fa37927`. `main` apunta a `a66dbee0564f499db28a1f3c1ccf403198fe6371`, la misma base registrada en el run positivo #38 y en ambos PR. El árbol principal conserva el SHA aprobado y el índice vacío. La comparación anterior de Docker y Kind dio inventarios idénticos, incluidos IDs y estados de contenedores. Los inventarios se guardaron bajo `target/ep3-run38-negative`. Consulta la [matriz IE1–IE6](README.md#matriz-de-trazabilidad-ep3) en la guía de CI/CD.

## Validaciones complementarias del 27 de noviembre de 2026

- SonarScanner Maven actualizado de `3.11.0.3922` a `5.8.0.7211`. Pendiente de validación mediante GitHub Actions.
- Validación local mediante Docker, Maven 3.9 y Java 17: `mvn clean verify` finalizó con `BUILD SUCCESS`, código de salida 0 y duración de 2 minutos y 25 segundos.
- JaCoCo analizó 11 clases y aprobó el umbral mínimo de cobertura del 75 %.
- Dashboard Grafana actualizado con umbral de cobertura del 75 %, color rojo para incumplimiento y verde para cumplimiento.
- Grafana mostró 85,1 % de cobertura y 46,54 segundos de despliegue simulado correspondientes al run #38.
- SonarCloud PR #13: Quality Gate PASSED, cobertura de código nuevo del 95,65 %, duplicación del 0,0 %, cero issues nuevos y cero security hotspots. Se observó una advertencia por versión antigua del scanner.
- Los cinco ZIP originales del run #38 fueron verificados nuevamente mediante SHA-256. Todos coinciden con los digests registrados.
- Los artefactos fueron extraídos en `Downloads/Evidencias-EP3/Run38-Recuperado`, fuera del directorio temporal `target`.
- El entorno aislado `ep3-run38-evidence` conserva sus cinco contenedores operativos.
- Actuator confirmó estado general UP, PostgreSQL UP, liveness UP y readiness UP. La respuesta se guardó en `EP3_Actuator_Health.json`.
- La ejecución de Maven clean eliminó las carpetas temporales de evidencias. Los ZIP originales permanecen íntegros, aunque los registros locales derivados requieren recuperación o regeneración.

Las validaciones remotas de la nueva versión de SonarScanner, la protección efectiva de main y la reconciliación de identificadores de imagen continúan pendientes.
