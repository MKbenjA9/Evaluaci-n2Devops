# Order Manager API — Evaluación Parcial 3 de Ingeniería DevOps (DOY0101)

Order Manager es una API REST para crear pedidos, agregar ítems y avanzar su estado. La Evaluación Parcial 3 incorpora observabilidad en Docker Compose y despliegues en Kubernetes con kind y Amazon EKS.

## Arquitectura

| Capa | Componentes |
| --- | --- |
| Aplicación | Java 17, Spring Boot 4.0.10, Spring Data JPA, Validation, Actuator y Micrometer |
| Datos | PostgreSQL 16 con almacenamiento persistente. El perfil Maven local utiliza H2 en memoria |
| Métricas | Prometheus recolecta `/actuator/prometheus`. Grafana aprovisiona el dashboard Order Manager API |
| Logs | Alloy filtra registros de la API y PostgreSQL. Loki configura una retención de siete días |
| Ejecución | Docker Compose, Kustomize y Helm. El Dockerfile multietapa compila con Maven y ejecuta con un usuario sin privilegios |
| CI | GitHub Actions ejecuta Maven, JaCoCo, Gitleaks, SonarCloud, Trivy y un despliegue simulado con pruebas HTTP |

En Compose, Alloy lee los dos contenedores permitidos mediante un proxy. El proxy tiene acceso al socket de Docker y queda reservado para el laboratorio local. En Kubernetes, Alloy usa la API de Kubernetes con RBAC acotado al namespace de la aplicación. Consulta el [diseño y pruebas del proxy](monitoring/docker-logs-proxy/README.md) y la [guía de Kubernetes](k8s/README.md).

## Docker Compose

Requisitos para Windows. Docker Desktop con contenedores Linux, Docker Compose v2 y PowerShell. Ejecuta los comandos desde la raíz. Para una instalación nueva, copia la plantilla y configura ambas contraseñas en el archivo local.

~~~powershell
if (-not (Test-Path .env)) { Copy-Item .env.example .env }
notepad .env
docker compose config --quiet
docker compose up -d --build
docker compose ps
~~~

| Variable | Uso |
| --- | --- |
| `DB_USER` | Obligatoria. Usuario inicial de PostgreSQL y usuario de la API |
| `DB_PASSWORD` | Obligatoria. Contraseña de PostgreSQL y de la conexión desde la API |
| `GRAFANA_ADMIN_PASSWORD` | Obligatoria. Contraseña inicial del administrador de Grafana |
| `DB_NAME` | Opcional. Base de datos, por defecto `orderdb` |
| `DOCKER_SOCKET_GID` | Opcional. Grupo con acceso al socket del motor Docker, por defecto `0`. Configura el GID real si difiere |

Guarda valores únicos en el archivo local ignorado o en el entorno del proceso. Si reutilizas un volumen, configura el usuario, nombre de base de datos y credenciales vigentes. Cambiar las variables de inicialización por sí solo no rota las credenciales de PostgreSQL ni Grafana. La contraseña histórica de PostgreSQL está retirada de la configuración y permanece en el historial de Git. Coordina su rotación donde se haya usado antes de compartir o publicar el repositorio.

### Verificación local

| Servicio | Acceso Compose |
| --- | --- |
| API | [http://127.0.0.1:8098](http://127.0.0.1:8098/actuator/health) |
| PostgreSQL | `127.0.0.1:5432` |
| Prometheus | [http://127.0.0.1:9090](http://127.0.0.1:9090/targets) |
| Grafana | [http://127.0.0.1:3000](http://127.0.0.1:3000/) |

Loki, Alloy y el proxy se comunican por redes internas. La API de laboratorio carece de autenticación. Usa pedidos sintéticos.

~~~powershell
Invoke-RestMethod http://127.0.0.1:8098/actuator/health
(Invoke-WebRequest http://127.0.0.1:8098/actuator/prometheus).StatusCode
Invoke-RestMethod http://127.0.0.1:8098/api/orders
(Invoke-RestMethod http://127.0.0.1:9090/api/v1/targets).data.activeTargets |
    Select-Object health, lastError
~~~

En Grafana abre **Dashboards → Order Manager API**. Los seis paneles operativos muestran CPU, heap JVM, disponibilidad de recolección, tasa HTTP, respuestas 4xx/5xx y latencia p95. La métrica `up` mide si Prometheus logra recolectar. Actuator informa la salud funcional, incluido PostgreSQL. El p95 requiere peticiones en la ventana consultada. Los dos paneles de CI muestran cobertura por líneas y tiempo de despliegue simulado al [importar un artefacto de una ejecución exitosa](ci/README.md#mediciones-y-grafana).

En **Explore → Loki**, consulta `{application="order-manager"}` para ver ambos servicios, `{application="order-manager"} |~ "^WARN "` para advertencias y `{application="order-manager"} |~ "^ERROR "` para errores. Para reproducir un 404, consulta un ID que sepas que no existe. Los registros conservan las etiquetas `application`, `service` y `container`.

### Apagado, reinicio y retiro

- **Apagado normal**. Ejecuta `docker compose stop` para conservar contenedores y volúmenes.
- **Reanudación o reinicio**. Usa `docker compose start` después de un apagado normal o `docker compose restart` para reiniciar los contenedores actuales. En un despliegue autorizado, aplica una imagen o configuración nueva con `docker compose up -d --build`.
- **Retiro del stack**. `docker compose down` elimina los contenedores y redes del proyecto y conserva sus volúmenes nombrados.

> **Eliminación definitiva.** `docker compose down -v` elimina los volúmenes de este proyecto y sus datos persistentes. Incluye PostgreSQL, históricos de Prometheus y Loki, estado de Grafana y posiciones de Alloy. Antes de ejecutarlo, confirma el proyecto objetivo, verifica respaldos y obtén autorización para descartar los datos.

## Kubernetes con kind

Requiere Docker, kind, kubectl y Helm. La [guía reproducible de kind](k8s/README.md) fija la imagen del nodo, construye y carga la imagen local, configura un kubeconfig aislado, crea los Secrets e instala PostgreSQL antes de la API. Aplica el overlay `k8s/overlays/local` e instala Alloy con Helm. Mantén el contexto explícito en cada comando.

Los port-forwards de la guía usan `127.0.0.1:18098` para la API, `127.0.0.1:13000` para Grafana y `127.0.0.1:19090` para Prometheus. El modo `Test-Lab.ps1 -CheckPersistence` crea marcadores y recrea pods con estado. Resérvalo para una validación autorizada.

## Amazon EKS y ECR

Requiere AWS CLI autenticada, Docker, kubectl, Helm y autorización para crear recursos. La [guía de EKS estándar](k8s/overlays/eks-local-storage/README.md) incluye prevalidaciones, plantillas, despliegue en `us-east-1`, comprobaciones y retiro controlado. El escenario validado usa Kubernetes 1.35, un Managed Node Group y `k8s/overlays/eks-local-storage`. Los port-forwards de evidencia usan los puertos `28098`, `23000` y `29090` para API, Grafana y Prometheus.

El flujo ECR construye una imagen `linux/amd64`, crea o selecciona un repositorio privado autorizado, inicia sesión mediante `aws ecr get-login-password` y `docker login --password-stdin`, publica una etiqueta y obtiene su digest con `aws ecr describe-images`. En una **copia** del overlay, cambia `images[].newName` por el registro y repositorio de la cuenta de destino y `images[].digest` por el digest publicado allí. Conserva `name: order-manager` y comprueba con `kubectl kustomize` que el Deployment use `repositorio@sha256:…`. El nodo necesita permisos de lectura sobre el registro. El digest incluido apunta a un artefacto privado anterior.

Las restricciones de IAM de Learner Lab impidieron validar Auto Mode y EBS CSI con las identidades disponibles. El [overlay Auto Mode](k8s/overlays/eks) y las [plantillas AWS](k8s/aws) documentan alternativas sujetas a permisos. El render local solo comprueba la estructura de esos manifiestos.

### Persistencia en EKS

PostgreSQL, Prometheus, Grafana y Loki usan PVC con `order-manager-local`, con afinidad al único nodo y datos en su disco raíz. La persistencia se verificó al recrear pods **en el mismo nodo**. El reemplazo o la terminación del nodo quedó fuera de la prueba. Ambas operaciones pueden volver inaccesibles los PV y eliminar datos si se elimina el disco raíz. `Retain` regula la reclamación del PV. EC2 gestiona por separado el ciclo de vida del disco. Para recuperar los datos en otro nodo se necesita un respaldo externo y una restauración.

EBS CSI permite provisionar discos independientes y adjuntarlos a un nodo compatible de la misma zona, sujeto a permisos y políticas. El almacenamiento local satisface el alcance de la prueba de recreación de pods. Los indicadores de la EP3 entregados por el equipo no exigen EBS CSI explícitamente. La [matriz de trazabilidad](ci/README.md#matriz-de-trazabilidad-ep3) distingue las evidencias disponibles y pendientes.

## Pruebas y CI

Con Java 17 y Maven, ejecuta `mvn -B clean verify`. Para repetir las pruebas Maven con Docker consulta la [guía de validación](k8s/README.md#validación-y-despliegue). Para el proxy usa `docker buildx build --progress plain --output type=cacheonly monitoring/docker-logs-proxy`.

La suite Maven cubre el controlador, el servicio, las validaciones y la persistencia. Las tres pruebas Go verifican la política de acceso del proxy y los campos devueltos. La prueba de migración usa un PostgreSQL 16 temporal para crear un pedido con Spring Boot 3.5 y verificar su lectura con Spring Boot 4. Consulta los [resultados de la migración y la validación local](ci/migracion-spring-boot-4.md).

La auditoría previa verificó Actuator, Prometheus, Grafana, logs y PVC en los tres entornos desplegados. Quedan pendientes una ejecución remota del workflow, una nueva validación funcional después de desplegar estas correcciones y la observación de la purga efectiva de Loki.

GitHub Actions genera y enmascara credenciales efímeras de Compose. La limpieza con volúmenes se aplica al proyecto efímero del runner. Antes de desplegar, CI exige pruebas Maven, un mínimo del 75 % de cobertura por líneas, Gitleaks, el Quality Gate de SonarCloud y la política de Trivy. Consulta los [controles y el procedimiento para obtener evidencias](ci/README.md).

Spring Boot 4.0.10 incorpora Spring Framework 7.0.11 y mantiene Java 17 como mínimo. [Requisitos oficiales](https://docs.spring.io/spring-boot/4.0/system-requirements.html)


<details>
<summary>Declaración y aportes de la Evaluación Parcial 2</summary>

## 9. Declaración de Uso de Inteligencia Artificial (IA)

En cumplimiento de las normativas éticas y formativas de la asignatura:

- **Herramientas utilizadas:** Asistente de IA (Antigravity IDE / Gemini).
- **Alcance y aplicación:** Apoyo en auditoría técnica de dependencias, estructuración de archivos de configuración estándar (Dockerfile, docker-compose.yml, dependabot.yml, workflows de GitHub Actions) y redacción técnica de la documentación de arquitectura.
- **Validación:** Todas las configuraciones, scripts y pruebas fueron auditados y verificados técnicamente sobre los requisitos oficiales de la Evaluación Parcial 2.

> [!IMPORTANT]
> ### Reflexiones Personales y Conclusiones Individuales (Sin IA)
> Conforme a la pauta oficial (*"Cada integrante debe incluir en la sección de conclusiones una reflexión personal, redactada sin apoyo de IA, explicando su aprendizaje y contribución al proyecto"*), este apartado queda reservado para la redacción manual de cada estudiante:
> 
### Reflexión Personal — Benjamin 
“Durante este proyecto aprendí la importancia de utilizar herramientas como Docker, GitHub Actions, SonarCloud y Trivy para automatizar procesos y mejorar la seguridad del código. También pude enfrentar y solucionar errores durante la configuración, lo que me ayudó a reforzar mis conocimientos. En conclusión, esta experiencia me permitió mejorar mis habilidades y comprender mejor cómo DevOps facilita el desarrollo de aplicaciones seguras y estables.”

### Reflexión Personal — Dylan Monroy
> "Al trabajar en este encargo me di cuenta de lo mucho que la automatización nos evita errores tontos en el día a día. Pasar de correr los tests y armar los contenedores a mano a tener un pipeline que se encarga de todo ,Desde probar el código hasta empaquetar con Docker Compose.te da otra seguridad antes de subir cambios. Me sirvió bastante aprender a rastrear cada versión con el hash de Git y ver cómo el trabajo en equipo con las ramas y las alertas de Dependabot ayudan a que el proyecto no se vuelva un caos. En resumen, entendí que DevOps no es solo meter herramientas, sino armar un flujo ordenado y estable para que las cosas no se rompan en el camino."

### Reflexión Personal — Nicolas Silva
> "Durante este proyecto aprendí la importancia de utilizar herramientas DevOps como Docker, GitHub Actions y las pruebas automatizadas para facilitar el desarrollo y despliegue de aplicaciones. También comprendí cómo herramientas como SonarCloud y Trivy ayudan a mejorar la calidad del código y detectar posibles vulnerabilidades. Aunque surgieron dificultades durante la configuración y ejecución del proyecto, pude comprender mejor cómo resolver problemas técnicos. En conclusión, esta experiencia me permitió aplicar los conocimientos adquiridos en Ingeniería en Informática y fortalecer mis habilidades para futuros proyectos."

</details>
