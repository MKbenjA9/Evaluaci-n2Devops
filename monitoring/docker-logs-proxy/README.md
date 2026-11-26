# Acceso de Alloy a los logs de Docker

Alloy necesita leer stdout y stderr y consultar si el contenedor está en ejecución y si usa TTY. El proxy admite negociación de la API, inspección reducida y lectura de logs exclusivamente para `order-manager-api` y `order-manager-db`. La inspección completa de Docker incluye el entorno del contenedor. Un proxy con permisos generales de lectura seguiría permitiendo esa consulta y podría entregar credenciales.

La red del proxy es interna y solo contiene el proxy y Alloy. El proceso del proxy usa un UID sin privilegios y el grupo del socket. Si el socket Linux usa un GID distinto de 0, configura `DOCKER_SOCKET_GID` en el entorno local con ese GID y conserva los permisos originales del socket.

El proxy conserva acceso al daemon y el montaje `:ro` no restringe los métodos de su API. Un fallo o compromiso del proceso podría permitir operaciones con los privilegios del socket. Las pruebas comprueban la lista de rutas, métodos y parámetros permitidos y los campos públicos de inspección. El endpoint de logs todavía transporta el texto original dentro de la red privada del proxy. Alloy conserva severidad y fragmentos fijos antes de enviar a Loki, y sustituye el resto por `[message withheld]`.
