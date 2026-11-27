# Migración local a Spring Boot 4 · EP3

Rama `feature/evaluacion-3` · 26 de noviembre de 2026.

## Compatibilidad y cambios

Spring Boot 4.0.10 es una versión estable que administra Spring Framework 7.0.11. Admite Java 17 y Maven 3.6.3 o posterior. Se validó con Java 17 y Maven 3.9.9. El servidor PostgreSQL de la prueba permaneció en la versión 16.16. [Requisitos](https://docs.spring.io/spring-boot/4.0/system-requirements.html) · [Dependencias administradas](https://docs.spring.io/spring-boot/4.0/appendix/dependency-versions/coordinates.html) · [Guía de migración](https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.0-Migration-Guide)

Se adoptaron el starter modular de Spring MVC, los starters de pruebas MVC y JPA, y el módulo de consola H2. Las pruebas cambiaron a `@MockitoBean` y a los paquetes de auto-configuración de Boot 4. Jackson 3 usa valores predeterminados compatibles con Jackson 2 mediante `spring.jackson.use-jackson2-defaults=true`. El perfil Docker habilita explícitamente los grupos liveness y readiness. Se conserva el modelo de datos y el código de validación y sanitización.

JaCoCo 0.8.11 conserva el gate del 75 % y la generación de HTML y XML. El pipeline compila con Java 17, conserva el scanner Maven 3.11.0.3922 en Java 21 y envía el XML de JaCoCo a SonarCloud. Java 21 corresponde al runtime del scanner. SonarCloud admite código Java 17. La autenticación y el Quality Gate se verifican en una ejecución remota autorizada. [Requisitos del scanner](https://docs.sonarsource.com/sonarqube-server/analyzing-source-code/scanners/scanner-environment/general-requirements) · [Soporte de Java](https://docs.sonarsource.com/sonarqube-cloud/advanced-setup/languages/java)

| Componente | Boot 3.5 | Boot 4.0 |
| --- | --- | --- |
| Spring Boot y Actuator | 3.5.16 | 4.0.10 |
| Spring Framework y MVC | 6.2.19 | 7.0.11 |
| Spring Data Commons | 3.5.13 | 4.0.9 |
| Jackson Core y Databind | 2.21.7 | 3.1.8 |
| Hibernate ORM | 6.6.53.Final | 7.2.25.Final |
| Tomcat embebido | 10.1.59 | 11.0.27 |
| JDBC PostgreSQL | 42.7.12 | 42.7.14 |
| Micrometer Core | 1.15.12 | 1.16.9 |
| H2 | 2.3.232 | 2.4.240 |
| Maven en Docker | 3.9.9 | 3.9.9 |
| JaCoCo | 0.8.11 | 0.8.11 |
| Scanner Maven de SonarCloud | 3.11.0.3922 | 3.11.0.3922 |

Los árboles Maven están en `target/ep3-verified/target/dependencies.txt` y `target/ep3-boot4/maven-final/target/dependencies.txt`.

## Pruebas Maven

| Resultado | Boot 3.5 | Boot 4.0 |
| --- | ---: | ---: |
| Aprobadas / fallidas / omitidas | 37 / 0 / 0 | 38 / 0 / 0 |
| Cobertura de líneas | 162/194 (83,51 %) | 165/194 (85,05 %) |
| Cobertura de ramas | 38/60 (63,33 %) | 38/60 (63,33 %) |
| Gate obligatorio de líneas al 75 % | Aprobado | Aprobado |

Se conservaron las 37 pruebas y se añadió una prueba de creación con respuesta 201. Comprueba los nombres de los campos, el estado inicial, el formato de la fecha, el total y el ítem anidado. JaCoCo generó HTML y XML en `target/ep3-boot4/maven-final/target/site/jacoco/`.

## Alcance de los CVE

| CVE | Severidad de Trivy en Boot 3.5 | Severidad del fabricante | Funcionalidad afectada y uso local |
| --- | --- | --- | --- |
| CVE-2026-47884 | Crítica | Media | Renderizado con `XsltView`. Order Manager expone un controlador REST que devuelve entidades, sin resolutores de vistas XSLT personalizados ni rutas comodín de renderizado |
| CVE-2026-47890 | Crítica | Baja | Fragmentos de vistas enviados como Server-Sent Events. Los endpoints de pedidos responden JSON o HTTP 204 y no usan SSE |

Spring Framework 7.0.9 corrigió ambos CVE en la línea abierta. La política mantiene las severidades de Trivy y bloquea por código de salida ante cualquier hallazgo crítico. [CVE-2026-47884](https://spring.io/security/cve-2026-47884/) · [CVE-2026-47890](https://spring.io/security/cve-2026-47890/)

## Controles de seguridad

| Resultado del workflow en prueba local | Boot 3.5.16 | Boot 4.0.10 |
| --- | ---: | ---: |
| Altos | 0 | 0 |
| Críticos | 2 | 0 |
| Medios | 5 | 4 |
| Bajos o de severidad desconocida | 0 | 0 |
| Código de salida al generar el JSON | 0 | 0 |
| Código de salida del gate crítico | 1 | 0 |

Se confirmó la ausencia de los CVE-2026-47884 y CVE-2026-47890 en la imagen `order-manager:ep3-boot4-4010`. Trivy 0.74.0 usa el mismo digest que CI. Los escaneos se ejecutaron sin red, con las bases de vulnerabilidades y Java descargadas una sola vez. Se verificaron sus SHA-256 antes y después. La evidencia está en `target/ep3-boot4/trivy-boot3.json`, `trivy-boot4.json` y `trivy-db-sha256.txt`.

La comparación de todas las severidades en `trivy-boot3-all.json` y `trivy-boot4-all.json` registró cero hallazgos nuevos. También dejó de reportar el medio CVE-2026-49844 de Log4j. Persisten cuatro medios de la imagen base Alpine 3.24.4.

| Paquete base | Detectado | Corregido según Trivy | CVE pendientes |
| --- | --- | --- | --- |
| libexpat | 2.10.0-r0 | 2.11.0-r0 | CVE-2026-124317, CVE-2026-128241, CVE-2026-134703 |
| zlib | 1.3.2-r1 | 1.4-r0 | CVE-2026-4738 |

Gitleaks aprobó el árbol publicable con código 0 y devolvió 1 con el fixture sintético. El escaneo de secretos de imagen devolvió 0. El gate Trivy también aceptó el fixture sin críticos con código 0. El caso negativo de Maven produjo una aserción fallida y código 1. El caso negativo de JaCoCo produjo una violación de la regla al elevar solo en la copia de prueba el umbral al 100 % y devolvió 1.

## Integración y observabilidad

La prueba inició un PostgreSQL 16.16 en almacenamiento temporal y una red exclusiva. Boot 3.5 creó un pedido. La imagen Boot 4 se inició sobre esa misma base de prueba y devolvió el mismo JSON con los datos persistidos. Se comprobaron consulta por estado, adición de ítems, transiciones, conflicto, validación de entrada, borrado y error 404. Una falla inducida en la base desechable produjo HTTP 500 y permitió verificar el evento sanitizado. Actuator devolvió `UP` para salud, base de datos, liveness y readiness.

Prometheus raspó el Actuator de Boot 4 y devolvió valores reales para las seis consultas PromQL del dashboard. Alloy procesó desde un archivo los logs reales 404 y 500 de la prueba, con las etapas de sanitización de Compose, y Loki devolvió ambos eventos sanitizados. Las dos consultas LogQL de métricas CI devolvieron los valores sintéticos introducidos para verificar su compatibilidad. Los ocho paneles se validaron mediante consultas a sus fuentes. Sus datos reales de GitHub Actions y las capturas de Grafana quedan pendientes.

Pasaron la validación estática de Prometheus, Loki y Alloy para Compose y Kubernetes, `docker compose config --quiet` con variables temporales, los tres overlays de Kustomize, los tres scripts PowerShell y actionlint. Se ejecutaron las tres pruebas Go principales y sus subcasos sin caché. La prueba de observabilidad no concede acceso al socket Docker a Alloy. El proxy existente conserva sus pruebas Go.

La cobertura del pipeline sigue derivándose del XML JaCoCo. El tiempo se registra con reloj monotónico desde antes de Compose hasta la salud y el smoke test exitosos. Los jobs mantienen su dependencia y los pasos del despliegue simulado y publicación del JAR se ejecutan solo si los controles previos pasan. Los informes diagnósticos pueden conservarse cuando un gate falla.

## Cambios de archivos

- `pom.xml` incorpora el padre 4.0.10 y los módulos MVC, JPA de pruebas y consola H2. Las versiones de Tomcat y pgJDBC vuelven a la gestión del padre y el stack JSON usa Jackson 3.
- `application.properties` conserva los valores de serialización compatibles. `application-docker.properties` habilita los grupos de salud.
- `OrderControllerTest.java` y `OrderPersistenceTest.java` adaptan sus anotaciones. El controlador incorpora una prueba del contrato JSON para una creación exitosa.
- `README.md`, `ci/README.md` y `ci/remediacion-ep3.md` enlazan este informe y actualizan la trazabilidad. Los archivos de evidencia local están en `target/ep3-boot4/`.

## Estado de entrega

La rama pasó los controles locales para una futura revisión en GitHub. Quedan pendientes la autorización de publicación, el Quality Gate de SonarCloud, los checks de protección de rama, una ejecución exitosa y una negativa de GitHub Actions, la importación de métricas reales, las capturas de Grafana y la validación de Boot 4 en los despliegues autorizados. La [guía de CI](README.md) contiene la matriz IE1 a IE6.

El cotejo de ID, estado y horarios de los contenedores existentes dio cero diferencias. Los siete contenedores de Order Manager siguieron detenidos y Kind siguió activo. La validación usó recursos temporales propios y la imagen quedó local. Durante esta fase no se hicieron commits, push, cambios en GitHub o AWS, despliegues sobre entornos existentes ni cambios en `.env`.
