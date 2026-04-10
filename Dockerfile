# --- Etape 1 : Build avec Maven ---
FROM maven:3.9-eclipse-temurin-17-alpine AS build
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -B
COPY src src
RUN mvn package -DskipTests -B

# --- Etape 2 : Image finale légère ---
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app

# Création de l'utilisateur applicatif
RUN addgroup -S afrikpay && adduser -S afrikpay -G afrikpay
COPY --from=build /app/target/*.jar app.jar
RUN chown afrikpay:afrikpay app.jar

USER afrikpay
EXPOSE 8080

ENTRYPOINT ["java", "-jar", "app.jar"]
