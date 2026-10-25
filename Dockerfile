# ============================================================
# Etapa 1: Construcción (Build)
# ============================================================
FROM maven:3.9.9-eclipse-temurin-17-alpine AS builder
WORKDIR /build

# Aprovechar caché de capas para dependencias
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Compilar y empaquetar aplicación
COPY src ./src
RUN mvn clean package -DskipTests -B

# ============================================================
# Etapa 2: Imagen de ejecución (Runtime) optimizada y segura
# ============================================================
FROM eclipse-temurin:17-jre-alpine AS runtime

# Crear usuario y grupo sin privilegios de root (Seguridad y Gobernanza IE3)
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Copiar artefacto generado desde la etapa de compilación
COPY --from=builder /build/target/*.jar app.jar
RUN chown -R appuser:appgroup /app

# Ejecutar con usuario no privilegiado
USER appuser

# Puerto oficial del microservicio
EXPOSE 8098

# Parámetros de memoria y escalabilidad
ENV SPRING_PROFILES_ACTIVE=docker \
    JAVA_OPTS="-Xms256m -Xmx512m -XX:+UseG1GC"

# Verificación de salud interna del contenedor
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD wget -qO- http://localhost:8098/actuator/health || exit 1

# Punto de entrada
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
