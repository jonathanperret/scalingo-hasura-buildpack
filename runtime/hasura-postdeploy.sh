#!/bin/bash

# This postdeploy script is inspired by
# https://github.com/hasura/graphql-engine/blob/master/packaging/cli-migrations/v3/docker-entrypoint.sh
# but simplified and tailored for the Scalingo environment

set -euo pipefail

echo "Container memory: $CONTAINER_MEMORY"

function log() {
  TIMESTAMP=$(date -u "+%Y-%m-%dT%H:%M:%S.000+0000")
  LOGKIND=$1
  MESSAGE=$2
  echo "{\"timestamp\":\"$TIMESTAMP\",\"level\":\"info\",\"type\":\"startup\",\"detail\":{\"kind\":\"$LOGKIND\",\"info\":\"$MESSAGE\"}}"
}

: ${HASURA_GRAPHQL_MIGRATIONS_SERVER_PORT:=9691}
: ${HASURA_GRAPHQL_MIGRATIONS_SERVER_TIMEOUT:=30}
: ${HASURA_GRAPHQL_SEED_ON_DEPLOY:=false}

# wait for server to be ready
function wait_for_server() {
  local PORT=$1
  local response
  log "migrations-startup" "waiting $HASURA_GRAPHQL_MIGRATIONS_SERVER_TIMEOUT for $PORT to be ready"
  for _ in $(seq 1 $HASURA_GRAPHQL_MIGRATIONS_SERVER_TIMEOUT);
  do
    response=$(curl -Ss http://localhost:$PORT/healthz 2>/dev/null || true)
    if [[ "$response" == "OK" ]]; then
      log "migrations-startup" "server on port $PORT is ready" && return
      return
    fi
    sleep 1
  done
  log "migrations-startup" "failed waiting for $PORT, try increasing HASURA_GRAPHQL_MIGRATIONS_SERVER_TIMEOUT (default: 30)" && exit 1
}

function start_server() {
  log "migrations-startup" "starting graphql engine temporarily on port $HASURA_GRAPHQL_MIGRATIONS_SERVER_PORT"

    # start graphql engine with metadata api enabled
    graphql-engine serve --enabled-apis="metadata" \
      --server-port=${HASURA_GRAPHQL_MIGRATIONS_SERVER_PORT}  &
          # store the pid to kill it later
          PID=$!

    # wait for port to be ready
    wait_for_server $HASURA_GRAPHQL_MIGRATIONS_SERVER_PORT
  }

  start_server

# apply metadata if the directory exists
if [ -d metadata ]; then
  log "migrations-apply" "applying metadata from 'metadata'"

  echo "version: 3" > config.yaml
  echo "endpoint: http://localhost:$HASURA_GRAPHQL_MIGRATIONS_SERVER_PORT" >> config.yaml
  echo "metadata_directory: metadata" >> config.yaml
  hasura --no-color metadata apply
else
  log "migrations-apply" "directory 'metadata' does not exist, skipping metadata"
fi

# apply migrations if the directory exists
if [ -d migrations ]; then
  log "migrations-apply" "applying migrations from 'migrations'"

  echo "version: 3" > config.yaml
  echo "endpoint: http://localhost:$HASURA_GRAPHQL_MIGRATIONS_SERVER_PORT" >> config.yaml
  echo "migrations_directory: migrations" >> config.yaml

  hasura --no-color migrate apply --all-databases
  log "migrations-apply" "reloading metadata"
  hasura --no-color metadata reload
else
  log "migrations-apply" "directory 'migrations' does not exist, skipping migrations"
fi

# apply seeds if requested and the directory exists
if [[ -d seeds ]]; then
  if [[ "$HASURA_GRAPHQL_SEED_ON_DEPLOY" == "true" ]]; then
    log "seeds-apply" "applying seeds from 'seeds'"

    echo "version: 3" > config.yaml
    echo "endpoint: http://localhost:$HASURA_GRAPHQL_MIGRATIONS_SERVER_PORT" >> config.yaml

    # Since "hasura seeds apply" does not have an --all-databases flag, we need
    # to find the database name in case it is not "default"...
    database_name=$(ruby -ryaml -e 'puts YAML.load_file(ARGV[0]).first["name"]' \
      -- "metadata/databases/databases.yaml"
    )

    hasura --no-color seeds apply --database-name="$database_name"
  else
    log "seeds-apply" "variable HASURA_GRAPHQL_SEED_ON_DEPLOY is not set to 'true', skipping seeds"
  fi
else
  log "seeds-apply" "directory 'seeds' does not exist, skipping seeds"
fi

# kill graphql engine that we started earlier
log "migrations-shutdown" "killing temporary server"
kill $PID

# wait for engine to exit
wait
