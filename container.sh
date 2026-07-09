#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# Images
# ============================================================

POSTGRES_IMAGE="docker.io/library/postgres:15"
REDIS_IMAGE="docker.io/library/redis:7.2-alpine"

# Docker Hub digunakan untuk menghindari rate limit dari
# docker.redpanda.com.
REDPANDA_IMAGE="docker.io/redpandadata/redpanda:v26.1.12"

KEYCLOAK_IMAGE="quay.io/keycloak/keycloak:26.4.7"
VOLUME_INIT_IMAGE="docker.io/library/alpine:3.20"

# ============================================================
# Container names
# ============================================================

POSTGRES_CONTAINER="durianpay_postgres"
REDIS_CONTAINER="durianpay_redis"
REDPANDA_CONTAINER="redpanda"
REDPANDA_VOLUME_INIT_CONTAINER="redpanda_volume_init"
KEYCLOAK_CONTAINER="keycloak"

# ============================================================
# Apple Container volumes
#
# Nama volume sengaja berbeda dari Docker Compose:
# - pg_data
# - redis_data
# - redpanda_data
# ============================================================

POSTGRES_VOLUME="apple_durianpay_pg_data"
REDIS_VOLUME="apple_durianpay_redis_data"
REDPANDA_VOLUME="apple_durianpay_redpanda_data"

# Root volume PostgreSQL dapat memiliki lost+found.
# Karena itu, PostgreSQL disimpan di subdirectory.
POSTGRES_DATA_PATH="/var/lib/postgresql/data/pgdata"

# ============================================================
# Port mappings
#
# Host port = original port + 1
# ============================================================

POSTGRES_HOST_PORT="5433"
REDIS_HOST_PORT="6380"
REDPANDA_KAFKA_HOST_PORT="9093"
REDPANDA_ADMIN_HOST_PORT="9645"
KEYCLOAK_HOST_PORT="8081"

# ============================================================
# PostgreSQL configuration
# ============================================================

POSTGRES_DB="durianpay_db"
POSTGRES_USER="admin"
POSTGRES_PASSWORD="admin"

# ============================================================
# Helpers
# ============================================================

log() {
  printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$1"
}

fail() {
  printf '\nError: %s\n' "$1" >&2
  exit 1
}

container_exists() {
  container inspect "$1" >/dev/null 2>&1
}

volume_exists() {
  container volume inspect "$1" >/dev/null 2>&1
}

remove_container() {
  local name="$1"

  if container_exists "$name"; then
    log "Removing existing container: ${name}"
    container delete --force "$name" >/dev/null
  fi
}

create_volume() {
  local name="$1"

  if volume_exists "$name"; then
    log "Using existing volume: ${name}"
  else
    log "Creating volume: ${name}"
    container volume create "$name"
  fi
}

show_container_logs() {
  local name="$1"

  echo
  echo "Logs for ${name}:"
  container logs "$name" 2>/dev/null || true
}

wait_for_postgres() {
  local max_attempts=60
  local attempt

  log "Waiting for PostgreSQL"

  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    if container exec "$POSTGRES_CONTAINER" \
      pg_isready \
      --username "$POSTGRES_USER" \
      --dbname "$POSTGRES_DB" >/dev/null 2>&1; then

      log "PostgreSQL is ready"
      return 0
    fi

    printf '.'
    sleep 2
  done

  printf '\n'
  show_container_logs "$POSTGRES_CONTAINER"
  fail "PostgreSQL failed to become ready"
}

get_redpanda_user() {
  local redpanda_id

  log "Detecting Redpanda container UID and GID"

  redpanda_id="$(
    container run \
      --rm \
      --progress none \
      --entrypoint /bin/sh \
      "$REDPANDA_IMAGE" \
      -c 'printf "%s:%s" "$(id -u)" "$(id -g)"'
  )"

  REDPANDA_UID="${redpanda_id%%:*}"
  REDPANDA_GID="${redpanda_id##*:}"

  if [[ ! "$REDPANDA_UID" =~ ^[0-9]+$ ]]; then
    fail "Unable to detect Redpanda UID: ${REDPANDA_UID}"
  fi

  if [[ ! "$REDPANDA_GID" =~ ^[0-9]+$ ]]; then
    fail "Unable to detect Redpanda GID: ${REDPANDA_GID}"
  fi

  log "Redpanda runs as UID=${REDPANDA_UID}, GID=${REDPANDA_GID}"
}

prepare_redpanda_volume() {
  log "Preparing Redpanda volume permissions"

  remove_container "$REDPANDA_VOLUME_INIT_CONTAINER"

  container run \
    --rm \
    --name "$REDPANDA_VOLUME_INIT_CONTAINER" \
    --user 0:0 \
    --volume "${REDPANDA_VOLUME}:/data" \
    "$VOLUME_INIT_IMAGE" \
    sh -ec "
      mkdir -p /data/crash_reports

      chown -R \
        '${REDPANDA_UID}:${REDPANDA_GID}' \
        /data

      chmod -R u+rwX,g+rwX /data

      echo 'Redpanda volume permissions:'
      ls -ldn /data
      ls -ldn /data/crash_reports
    "

  log "Redpanda volume permissions are ready"
}

# Remove the temporary init container if the script is interrupted.
cleanup() {
  container delete \
    --force \
    "$REDPANDA_VOLUME_INIT_CONTAINER" >/dev/null 2>&1 || true
}

trap cleanup EXIT

# ============================================================
# Prerequisite checks
# ============================================================

if ! command -v container >/dev/null 2>&1; then
  fail "Apple Container CLI is not installed or not available in PATH"
fi

# ============================================================
# Start Apple Container system
# ============================================================

log "Checking Apple Container system"

if ! container system status >/dev/null 2>&1; then
  log "Starting Apple Container system"
  container system start
fi

# ============================================================
# Remove old containers
#
# Named volumes are intentionally preserved.
# ============================================================

remove_container "$KEYCLOAK_CONTAINER"
remove_container "$REDPANDA_CONTAINER"
remove_container "$REDPANDA_VOLUME_INIT_CONTAINER"
remove_container "$REDIS_CONTAINER"
remove_container "$POSTGRES_CONTAINER"

# Cleanup from an older version of this script.
remove_container "unleash"

# ============================================================
# Create persistent volumes
# ============================================================

create_volume "$POSTGRES_VOLUME"
create_volume "$REDIS_VOLUME"
create_volume "$REDPANDA_VOLUME"

# ============================================================
# PostgreSQL
#
# Host:      localhost:5433
# Container: 5432
# ============================================================

log "Starting PostgreSQL"

container run \
  --detach \
  --name "$POSTGRES_CONTAINER" \
  --env "POSTGRES_DB=${POSTGRES_DB}" \
  --env "POSTGRES_USER=${POSTGRES_USER}" \
  --env "POSTGRES_PASSWORD=${POSTGRES_PASSWORD}" \
  --env "PGDATA=${POSTGRES_DATA_PATH}" \
  --publish "127.0.0.1:${POSTGRES_HOST_PORT}:5432" \
  --volume "${POSTGRES_VOLUME}:/var/lib/postgresql/data" \
  "$POSTGRES_IMAGE"

wait_for_postgres

# ============================================================
# Redis
#
# Host:      localhost:6380
# Container: 6379
# ============================================================

log "Starting Redis"

container run \
  --detach \
  --name "$REDIS_CONTAINER" \
  --publish "127.0.0.1:${REDIS_HOST_PORT}:6379" \
  --volume "${REDIS_VOLUME}:/data" \
  "$REDIS_IMAGE"

# ============================================================
# Prepare Redpanda volume
#
# Apple Container named volumes can initially be root-owned,
# while Redpanda normally runs as a non-root user.
# ============================================================

get_redpanda_user
prepare_redpanda_volume

# ============================================================
# Redpanda
#
# Kafka:
#   Host:      localhost:9093
#   Container: 9092
#
# Admin API:
#   Host:      localhost:9645
#   Container: 9644
# ============================================================

log "Starting Redpanda"

container run \
  --detach \
  --name "$REDPANDA_CONTAINER" \
  --cpus 1 \
  --memory 2G \
  --publish "127.0.0.1:${REDPANDA_KAFKA_HOST_PORT}:9092" \
  --publish "127.0.0.1:${REDPANDA_ADMIN_HOST_PORT}:9644" \
  --volume "${REDPANDA_VOLUME}:/var/lib/redpanda/data" \
  "$REDPANDA_IMAGE" \
  redpanda start \
  --mode dev-container \
  --smp 1 \
  --memory 1G \
  --reserve-memory 0M \
  --node-id 0 \
  --check=false \
  --kafka-addr "external://0.0.0.0:9092" \
  --advertise-kafka-addr \
    "external://localhost:${REDPANDA_KAFKA_HOST_PORT}" \
  --set redpanda.auto_create_topics_enabled=true

# ============================================================
# Keycloak
#
# Host:      http://localhost:8081
# Container: 8080
#
# Keycloak menggunakan database development internal.
# ============================================================

log "Starting Keycloak"

container run \
  --detach \
  --name "$KEYCLOAK_CONTAINER" \
  --memory 2G \
  --env KC_BOOTSTRAP_ADMIN_USERNAME=admin \
  --env KC_BOOTSTRAP_ADMIN_PASSWORD=admin \
  --publish "127.0.0.1:${KEYCLOAK_HOST_PORT}:8080" \
  "$KEYCLOAK_IMAGE" \
  start-dev

# ============================================================
# Result
# ============================================================

log "All containers have been started"

cat <<EOF

Services:

  PostgreSQL
    Address:  localhost:${POSTGRES_HOST_PORT}
    Database: ${POSTGRES_DB}
    Username: ${POSTGRES_USER}
    Password: ${POSTGRES_PASSWORD}
    PGDATA:   ${POSTGRES_DATA_PATH}

  Redis
    Address: localhost:${REDIS_HOST_PORT}

  Redpanda Kafka
    Address: localhost:${REDPANDA_KAFKA_HOST_PORT}

  Redpanda Admin API
    Address: http://localhost:${REDPANDA_ADMIN_HOST_PORT}

  Keycloak
    Address:  http://localhost:${KEYCLOAK_HOST_PORT}
    Username: admin
    Password: admin

Volumes:

  PostgreSQL: ${POSTGRES_VOLUME}
  Redis:      ${REDIS_VOLUME}
  Redpanda:   ${REDPANDA_VOLUME}

Container status:
EOF

container list --all