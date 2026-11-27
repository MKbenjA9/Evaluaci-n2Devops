# Rotación de PostgreSQL · procedimiento por entorno

En Docker Compose local se confirmó por TCP que la contraseña histórica funcionaba antes de la rotación y que PostgreSQL la rechaza después. La credencial nueva fue aceptada por PostgreSQL y por la API. El respaldo se restauró en una instancia aislada antes del cambio. Se preservaron el volumen y las imágenes existentes, y los conteos y las huellas de las tablas coincidieron después de la rotación.

La revisión anterior del Secret `order-manager/postgres-auth` de Kind encontró un valor distinto al histórico. La autenticación efectiva en Kind y el estado de EKS quedan pendientes de verificación. La configuración de un contenedor o un Secret solo acredita qué valor se le proporcionó, mientras que PostgreSQL mantiene su estado de autenticación en el directorio de datos.

## Preparación común

1. Programar una ventana por entorno y confirmar el contexto, el rol de aplicación, el nombre de la base y el volumen o PVC que la contiene. Mantener una sesión administrativa independiente y operativa durante toda la ventana.
2. Hacer un respaldo lógico `pg_dump -Fc` en almacenamiento protegido fuera de Git, comprobarlo con `pg_restore --list` y ensayar la restauración solo en PostgreSQL 16 aislado. Registrar también las propiedades y permisos del rol necesarios para recuperar el acceso. Registrar identificadores del volumen, PV/PVC y, en EKS con almacenamiento local, el nodo. Mantener la vinculación existente.
3. Generar una credencial nueva por entorno en el gestor aprobado. Pausar escrituras si corresponde. Cambiar la contraseña del rol existente desde la sesión administrativa mediante `\password nombre_del_rol`, con entrada interactiva. Usar un canal protegido y mantener el valor fuera de argumentos, stdout, historial y archivos versionados. [PostgreSQL 16 · ALTER ROLE](https://www.postgresql.org/docs/16/sql-alterrole.html)
4. Actualizar el consumidor del secreto y probar una conexión nueva con autenticación por contraseña mediante la ruta de red que usa la API. Confirmar salud del componente `db`, lectura y escritura de prueba controlada y contenedores o pods saludables. Comprobar por separado que la credencial histórica falla mediante esa misma ruta si estaba activa. Una sesión ya abierta o un socket local con autenticación de confianza no prueban la rotación.
5. Ante un fallo, usar la sesión administrativa retenida para sincronizar el rol y la configuración con una credencial nueva de recuperación. Preservar los volúmenes y revalidar el acceso. Reservar el respaldo para una recuperación de datos real.

## Compose

- Identificar el proyecto y el volumen en uso antes de intervenir. Actualizar `DB_PASSWORD` en el origen de configuración protegido. El `.env` versionable sigue siendo `.env.example`.
- Recrear solo la API del proyecto autorizado para cargar el valor. Mantener PostgreSQL en su volumen existente. Si el contenedor de PostgreSQL conserva el valor histórico en su metadata, programar su recreación por separado, verificando el montaje del mismo volumen y el estado de la base. Cambiar `POSTGRES_PASSWORD` en el entorno de un contenedor con datos inicializados requiere ejecutar también el cambio SQL del rol.
- Evitar `docker compose down -v`, la eliminación del volumen y cualquier inicialización de una base nueva.

## Kind y EKS

- Usar el contexto explícito y el namespace `order-manager`. Actualizar únicamente la clave `password` de `postgres-auth` mediante el canal aprobado de secretos, conservando `username` y el resto de claves. Aplicar el cambio del rol SQL y reiniciar de forma controlada el Deployment de Order Manager para que lea el valor nuevo.
- Mantener StatefulSet, PVC y PV vinculados. Si se requiere renovar el entorno del pod PostgreSQL, planificarlo por separado con el mismo almacenamiento y esperar su readiness. En EKS con almacenamiento local, confirmar antes la afinidad al nodo, la ubicación del respaldo externo y la disponibilidad del nodo. El reemplazo del nodo puede dejar el volumen inaccesible. [Limitaciones de almacenamiento local](../k8s/overlays/eks-local-storage/README.md)

La rotación se ejecutó exclusivamente en Compose local. Las intervenciones en Kind y EKS requieren autorización separada. El historial de Git conserva los commits originales.
