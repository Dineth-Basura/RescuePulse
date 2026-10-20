FROM ballerina/ballerina:2201.13.6 AS build
WORKDIR /home/ballerina/project
COPY --chown=ballerina:ballerina backend/src/ ./
RUN bal build
FROM eclipse-temurin:21-jre
WORKDIR /app/backend/src
COPY --from=build /home/ballerina/project/target/bin/backend.jar ./backend.jar
COPY frontend /app/frontend
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "backend.jar"]
