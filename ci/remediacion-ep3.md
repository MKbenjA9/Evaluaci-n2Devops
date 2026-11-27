# Remediación local de Order Manager · EP3

Rama `feature/evaluacion-3` · 26 de noviembre de 2026.

Este informe registra la fase con Spring Boot 3.5.16. Consulta el [informe de migración a Spring Boot 4](migracion-spring-boot-4.md) para el estado posterior.

**La versión queda bloqueada para publicar y desplegar.** La imagen corregida conserva dos hallazgos críticos de Spring MVC según Trivy. Se corrigieron 44 de los 45 hallazgos iniciales, incluidos los 36 altos y los ocho críticos de Tomcat. Un crítico persistió y apareció otro.

## Resultados de Trivy

| Alcance | Altas antes | Críticas antes | Altas después | Críticas después |
| --- | ---: | ---: | ---: | ---: |
| Dependencias Java | 36 | 9 | 0 | 2 |
| Paquetes del sistema base Alpine 3.24.4 | 0 | 0 | 0 | 0 |
| **Total** | **36** | **9** | **0** | **2** |

Se usó Trivy 0.74.0 con los mismos filtros de severidad que el workflow. Se compararon las etiquetas locales `order-manager:latest` y `order-manager:ep3-remediation-final`. El JSON de referencia reproduce los 45 hallazgos consignados en la evidencia previa. El archivo original de esa ejecución no apareció en la búsqueda local. Se conserva la referencia previa y, por separado, el JSON reproducido `target/ep3-remediation/trivy-before-rescan.json`. El informe posterior es `target/ep3-remediation/trivy-final.json`. Ambos informes se generaron con el escáner de vulnerabilidades. Los resultados de secretos se guardaron aparte con salida redactada o descartada.

| Informe JSON | SHA-256 |
| --- | --- |
| Referencia reproducida | `8fb7ce60b32cab42ba3fb7a5a05ffa3182ba27be33b7c610bb65f4fea1edafae` |
| Imagen final | `8f8151637727326aab0de47df2d8bfde7cff9d7f4e42e2d8c2a0c44e5c673230` |

El crítico `CVE-2026-47884` persiste y `CVE-2026-47890` apareció tras la actualización. Trivy los clasifica como críticos y devuelve código **1** en el control de publicación. Los avisos del fabricante los califican como medio y bajo, respectivamente. Se mantuvo la clasificación original del escáner. Spring publicó Spring Framework 7.0.9 como arreglo abierto y 6.2.20 como arreglo comercial para ambos CVE. La opción comercial requeriría acceso autorizado al repositorio del fabricante y una nueva validación de Trivy. Adoptar la línea abierta de Spring Framework 7 requiere una migración mayor compatible de Spring Boot. [CVE-2026-47884](https://spring.io/security/cve-2026-47884/) · [CVE-2026-47890](https://spring.io/security/cve-2026-47890/)

## Dependencias y base

Los árboles Maven completos están en `target/ep3-baseline/target/dependencies.txt` y `target/ep3-verified/target/dependencies.txt`.

| Componente | Anterior | Final | Entrada Maven |
| --- | --- | --- | --- |
| Spring Boot | 3.3.4 | 3.5.16 | POM padre. El JAR `spring-boot` llega por los starters |
| Spring MVC, Core y Expression | 6.1.13 | 6.2.19 | Transitivas del stack de starters Spring |
| Spring Data Commons | 3.3.4 | 3.5.13 | Transitiva de `spring-boot-starter-data-jpa` |
| Tomcat embebido | 10.1.30 | 10.1.59 | Transitiva de `spring-boot-starter-web` |
| Jackson Core y Databind | 2.17.2 | 2.21.7 | Transitivas de `spring-boot-starter-web` vía `spring-boot-starter-json` |
| Micrometer Core | 1.13.4 | 1.15.12 | Transitiva de Actuator y del registro Prometheus |
| JDBC PostgreSQL | 42.7.4 | 42.7.12 | Directa, alcance `runtime` |
| Eclipse Temurin 17 / Alpine | Alpine 3.24.4 | Alpine 3.24.4 | Base de ejecución de Docker, refrescada mediante `--pull` |

Spring Boot 3.5.16 admite Java 17 y es la última versión pública de la serie 3.5. Su soporte abierto terminó en junio de 2026. Se actualizaron Tomcat, Jackson y pgJDBC con propiedades de la gestión de dependencias del POM padre, después de que el escaneo de la primera imagen 3.5.16 identificara hallazgos en las versiones que trae por defecto. [Anuncio de Spring Boot 3.5.16](https://spring.io/blog/2026/06/25/spring-boot-3-5-16-available-now/) · [Requisitos de Java](https://docs.spring.io/spring-boot/3.5/system-requirements.html)

## Pruebas y cobertura

| Medición | Antes | Después |
| --- | ---: | ---: |
| Maven, aprobadas / fallidas / omitidas | 30 / 0 / 0 | 37 / 0 / 0 |
| JaCoCo, líneas | 147/194 (75,77 %) | 162/194 (83,51 %) |
| JaCoCo, ramas | 29/60 (48,33 %) | 38/60 (63,33 %) |

Se añadieron pruebas de persistencia y recarga con H2, valores por defecto, validación de ítems y transformación de excepciones de negocio en respuestas HTTP 400 y 409. El gate de 75 % se aplica en `mvn verify` y pasó con Java 17. Los informes finales están en `target/ep3-verified/target/site/jacoco/`, en HTML y XML.

## Validación integral

| Control | Resultado local |
| --- | --- |
| Pruebas Go del proxy Docker | 3 pruebas principales aprobadas, con subcasos, ejecutadas sin caché |
| Docker Compose | `config --quiet` pasó con variables temporales, sin iniciar servicios |
| Prometheus, Loki y Alloy | Validaciones de configuración aprobadas para Compose y Kubernetes |
| Kubernetes | Render exitoso de `local`, `eks` y `eks-local-storage` |
| Scripts PowerShell | Los tres archivos pasaron el análisis sintáctico |
| actionlint | Workflow válido |
| Maven negativo | Una aserción deliberadamente fallida en copia aislada, código 1 |
| JaCoCo negativo | Control deliberado al 100 % en copia aislada, código 1 |
| Gitleaks | Árbol publicable con salida redactada, código 0. Fixture sintético, código 1 |
| Trivy | Generación del JSON final, código 0. Gate crítico de referencia y final, código 1. Informe sintético sin críticos, código 0. Secretos altos y críticos en la imagen final, código 0 |
| Dashboard | Ocho paneles en el JSON que consumen Compose y Kubernetes. La guía conserva el procedimiento de importación de datos de un run real |
| `git diff --check` | Código 0. Se revisaron los archivos modificados y nuevos. `.env` y las evidencias de `target/` están excluidos por Git |

Los pasos de despliegue de Compose y publicación del JAR requieren que pasen los controles previos. Los pasos de diagnóstico pueden conservar informes de una ejecución fallida. La cobertura publicada se obtiene del XML JaCoCo y el tiempo de despliegue se mide con un reloj monotónico hasta que pasan la salud de la API y las pruebas HTTP. Esta fase no generó mediciones de despliegue en GitHub.

## Estado de entrega

- Cambios de esta fase en `pom.xml`, `.github/workflows/ci-cd.yml`, `OrderControllerTest.java` y `ci/README.md`. Archivos añadidos `OrderItemTest.java`, `OrderPersistenceTest.java` y este informe. El resto de los cambios locales pertenece al trabajo previo.
- En GitHub se requiere `SONAR_TOKEN`. `GITHUB_TOKEN` es automático y el umbral se encuentra en el POM. Véanse la configuración paso a paso, la matriz IE1–IE6 y el procedimiento de importación a Grafana en la [guía de CI/CD](README.md).
- Quedan pendientes el cierre de los dos CVE críticos, SonarCloud y las pruebas remotas de los controles, la verificación de reglas de rama, el artefacto de métricas de un run exitoso, su importación a Grafana y las capturas finales. La revisión Gitleaks de esta fase abarcó el árbol publicable. La remediación de credenciales históricas y la rotación de PostgreSQL siguen pendientes.
- El cotejo de los contenedores existentes arrojó cero diferencias en sus ID, estados y fechas de inicio o término. Los siete contenedores de Order Manager permanecieron detenidos y Kind conservó su estado activo. No se realizaron commits, push, cambios remotos, despliegues, rotaciones ni cambios en AWS, IAM, ECR o EKS.


## Inventario de CVE

Las versiones con parche de esta tabla provienen de Trivy. Spring también enumera la versión comercial 6.2.20 para los dos hallazgos pendientes. En los CVE presentes en la referencia, la columna de versión detectada muestra la versión inicial.

| CVE | Dependencia | Severidad Trivy | Versión detectada | Versiones corregidas según Trivy | Resultado |
| --- | --- | --- | --- | --- | --- |
| CVE-2026-47884 | org.springframework:spring-webmvc | CRITICAL | 6.1.13 | 7.0.9 | Persiste |
| CVE-2026-47890 | org.springframework:spring-webmvc | CRITICAL | 6.2.19 | 7.0.9 | Nuevo, pendiente |
| CVE-2026-68494 | com.fasterxml.jackson.core:jackson-core | HIGH | 2.17.2 | 2.18.8, 2.21.4 | Corregido |
| CVE-2026-89407 | com.fasterxml.jackson.core:jackson-core | HIGH | 2.17.2 | 2.18.11, 2.21.7, 2.22.3 | Corregido |
| CVE-2026-89425 | com.fasterxml.jackson.core:jackson-core | HIGH | 2.17.2 | 2.21.7, 2.22.3, 2.18.11 | Corregido |
| CVE-2026-54512 | com.fasterxml.jackson.core:jackson-databind | HIGH | 2.17.2 | 2.18.8, 3.1.4, 2.21.4 | Corregido |
| CVE-2026-54513 | com.fasterxml.jackson.core:jackson-databind | HIGH | 2.17.2 | 2.18.8, 2.21.4, 3.1.4 | Corregido |
| CVE-2026-68497 | com.fasterxml.jackson.core:jackson-databind | HIGH | 2.17.2 | 2.18.10, 2.21.6, 2.22.2 | Corregido |
| CVE-2026-91776 | com.fasterxml.jackson.core:jackson-databind | HIGH | 2.17.2 | 2.18.11, 2.21.7, 2.22.3 | Corregido |
| CVE-2026-91777 | com.fasterxml.jackson.core:jackson-databind | HIGH | 2.17.2 | 2.21.7, 2.18.11, 2.22.3 | Corregido |
| CVE-2026-40984 | io.micrometer:micrometer-core | HIGH | 1.13.4 | 1.16.6, 1.15.12 | Corregido |
| CVE-2024-50379 | org.apache.tomcat.embed:tomcat-embed-core | HIGH | 10.1.30 | 11.0.2, 10.1.34, 9.0.98 | Corregido |
| CVE-2024-56337 | org.apache.tomcat.embed:tomcat-embed-core | HIGH | 10.1.30 | 11.0.2, 10.1.34, 9.0.98 | Corregido |
| CVE-2025-24813 | org.apache.tomcat.embed:tomcat-embed-core | CRITICAL | 10.1.30 | 11.0.3, 10.1.35, 9.0.99 | Corregido |
| CVE-2025-48988 | org.apache.tomcat.embed:tomcat-embed-core | HIGH | 10.1.30 | 11.0.8, 10.1.42, 9.0.106 | Corregido |
| CVE-2025-48989 | org.apache.tomcat.embed:tomcat-embed-core | HIGH | 10.1.30 | 11.0.10, 10.1.44, 9.0.108 | Corregido |
| CVE-2025-52520 | org.apache.tomcat.embed:tomcat-embed-core | HIGH | 10.1.30 | 11.0.9, 10.1.43, 9.0.107 | Corregido |
| CVE-2025-53506 | org.apache.tomcat.embed:tomcat-embed-core | HIGH | 10.1.30 | 9.0.107, 10.1.43, 11.0.9 | Corregido |
| CVE-2025-55752 | org.apache.tomcat.embed:tomcat-embed-core | HIGH | 10.1.30 | 11.0.11, 10.1.45, 9.0.109 | Corregido |
| CVE-2026-24734 | org.apache.tomcat.embed:tomcat-embed-core | HIGH | 10.1.30 | 11.0.18, 10.1.52, 9.0.115 | Corregido |
| CVE-2026-24880 | org.apache.tomcat.embed:tomcat-embed-core | HIGH | 10.1.30 | 9.0.116, 10.1.52, 11.0.20 | Corregido |
| CVE-2026-34483 | org.apache.tomcat.embed:tomcat-embed-core | HIGH | 10.1.30 | 9.0.116, 10.1.54, 11.0.21 | Corregido |
| CVE-2026-34487 | org.apache.tomcat.embed:tomcat-embed-core | HIGH | 10.1.30 | 9.0.117, 10.1.54, 11.0.21 | Corregido |
| CVE-2026-41284 | org.apache.tomcat.embed:tomcat-embed-core | HIGH | 10.1.30 | 9.0.118, 10.1.55, 11.0.22 | Corregido |
| CVE-2026-41293 | org.apache.tomcat.embed:tomcat-embed-core | CRITICAL | 10.1.30 | 9.0.118, 10.1.55, 11.0.22 | Corregido |
| CVE-2026-42498 | org.apache.tomcat.embed:tomcat-embed-core | HIGH | 10.1.30 | 9.0.118, 10.1.55, 11.0.22 | Corregido |
| CVE-2026-43512 | org.apache.tomcat.embed:tomcat-embed-core | CRITICAL | 10.1.30 | 9.0.118, 10.1.55, 11.0.22 | Corregido |
| CVE-2026-43513 | org.apache.tomcat.embed:tomcat-embed-core | HIGH | 10.1.30 | 9.0.118, 10.1.55, 11.0.22 | Corregido |
| CVE-2026-43515 | org.apache.tomcat.embed:tomcat-embed-core | CRITICAL | 10.1.30 | 9.0.118, 10.1.55, 11.0.22 | Corregido |
| CVE-2026-53404 | org.apache.tomcat.embed:tomcat-embed-core | HIGH | 10.1.30 | 11.0.23, 10.1.56, 9.0.119 | Corregido |
| CVE-2026-55276 | org.apache.tomcat.embed:tomcat-embed-core | CRITICAL | 10.1.30 | 11.0.23, 10.1.56, 9.0.119 | Corregido |
| CVE-2026-55957 | org.apache.tomcat.embed:tomcat-embed-core | HIGH | 10.1.30 | 11.0.5, 10.1.37, 9.0.101 | Corregido |
| CVE-2026-65182 | org.apache.tomcat.embed:tomcat-embed-core | CRITICAL | 10.1.30 | 11.0.25, 10.1.58, 9.0.121 | Corregido |
| CVE-2026-65905 | org.apache.tomcat.embed:tomcat-embed-core | CRITICAL | 10.1.30 | 11.0.25, 10.1.58, 9.0.121 | Corregido |
| CVE-2026-68525 | org.apache.tomcat.embed:tomcat-embed-core | CRITICAL | 10.1.30 | 11.0.25, 10.1.58, 9.0.121 | Corregido |
| CVE-2025-49146 | org.postgresql:postgresql | HIGH | 42.7.4 | 42.7.7 | Corregido |
| CVE-2026-42198 | org.postgresql:postgresql | HIGH | 42.7.4 | 42.7.11 | Corregido |
| CVE-2026-54291 | org.postgresql:postgresql | HIGH | 42.7.4 | 42.7.12 | Corregido |
| CVE-2025-22235 | org.springframework.boot:spring-boot | HIGH | 3.3.4 | 3.3.11, 3.4.5 | Corregido |
| CVE-2026-40973 | org.springframework.boot:spring-boot | HIGH | 3.3.4 | 4.0.6, 3.5.14 | Corregido |
| CVE-2026-41716 | org.springframework.data:spring-data-commons | HIGH | 3.3.4 | 4.0.6, 3.5.12 | Corregido |
| CVE-2025-41249 | org.springframework:spring-core | HIGH | 6.1.13 | 6.2.11 | Corregido |
| CVE-2026-41850 | org.springframework:spring-expression | HIGH | 6.1.13 | 7.0.8, 6.2.19 | Corregido |
| CVE-2024-38819 | org.springframework:spring-webmvc | HIGH | 6.1.13 | 6.1.14 | Corregido |
| CVE-2026-41842 | org.springframework:spring-webmvc | HIGH | 6.1.13 | 7.0.8, 6.2.19 | Corregido |
| CVE-2026-41845 | org.springframework:spring-webmvc | HIGH | 6.1.13 | 7.0.8, 6.2.19 | Corregido |
