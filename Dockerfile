# Build stage: install the vendored jars that are not on Maven Central,
# then package the fat jar. This mirrors `mvn.sh full`.
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /build

COPY pom.xml ./
COPY src ./src

RUN mvn -B install:install-file -Dfile=src/main/resources/libs/jts-1.13.1.jar \
        -DgroupId=com.vividsolutions -DartifactId=jts -Dversion=1.13.1 -Dpackaging=jar \
 && mvn -B install:install-file -Dfile=src/main/resources/libs/geomason-1.5.2.jar \
        -DgroupId=sim.util.geo -DartifactId=geomason -Dversion=1.5.2 -Dpackaging=jar \
 && mvn -B install:install-file -Dfile=src/main/resources/libs/mason-19.jar \
        -DgroupId=sim -DartifactId=mason -Dversion=19 -Dpackaging=jar \
 && mvn -B install:install-file -Dfile=src/main/resources/libs/mason-tools-1.0.jar \
        -DgroupId=at.granul -DartifactId=mason-tools -Dversion=1.0 -Dpackaging=jar

RUN mvn -B -DskipTests clean package

# Runtime stage: headless batch simulation.
FROM eclipse-temurin:17-jre
WORKDIR /app

COPY --from=build /build/target/pol-0.2-jar-with-dependencies.jar jar/pol.jar
COPY run/maps ./maps
COPY run/modified.properties ./modified.properties

# Simulation output lands here. Mount a Railway volume at /data to persist it.
ENV SIM_OUTPUT=/data \
    SIM_TEST=c03 \
    SIM_UNTIL=100 \
    SIM_CONFIG=modified.properties \
    JAVA_OPTS=-XX:MaxRAMPercentage=75

# The log layer appends its own `logs/` subdirectory to log.rootDirectory.
# The closing manifest makes the persisted output visible in the deploy logs,
# which is the only view into the volume once this batch container exits.
CMD mkdir -p "$SIM_OUTPUT" && java \
      $JAVA_OPTS \
      -Djava.awt.headless=true \
      -Dlog4j2.configurationFactory=pol.log.CustomConfigurationFactory \
      -Dlog.rootDirectory="$SIM_OUTPUT" \
      -Dsimulation.test="$SIM_TEST" \
      -jar jar/pol.jar \
      -configuration "$SIM_CONFIG" \
      -until "$SIM_UNTIL" \
  && echo "=== simulation output in $SIM_OUTPUT ===" \
  && du -sh "$SIM_OUTPUT" \
  && ls -la "$SIM_OUTPUT/logs"
