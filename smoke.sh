#!/bin/bash
# Smoke test: usage smoke.sh <image> <mcphub version> <overlay node version>
# Starts MCPHub in database mode (pgvector, as in production) with a credential key file,
# then checks health, version, node, admin login against the database, the OAuth
# server metadata and that /mcp demands a bearer token.
set -euo pipefail
IMG=$1 VERSION=$2 NODE=$3
PG=docker.io/pgvector/pgvector:pg17-trixie
PORT=${SMOKE_PORT:-3000}

docker network create smoke >/dev/null
docker run -d --name smoke-db --network smoke -e POSTGRES_DB=mcphub -e POSTGRES_USER=mcphub \
  -e POSTGRES_PASSWORD=smoke "$PG" >/dev/null
DATA=${RUNNER_TEMP:-/tmp}/smoke-data
mkdir -p "$DATA"
openssl rand -base64 32 > "$DATA/mcp_settings.json.credentials.key"
cleanup() {
  docker logs --tail 80 smoke || true
  docker rm -f smoke smoke-db >/dev/null 2>&1 || true
  docker network rm smoke >/dev/null 2>&1 || true
}
trap cleanup EXIT

for i in $(seq 1 30); do docker exec smoke-db pg_isready -U mcphub -d mcphub >/dev/null 2>&1 && break; sleep 2; done

docker run -d --name smoke --network smoke -p "127.0.0.1:$PORT:3000" \
  -v "$DATA:/app/data" \
  -e DB_URL=postgresql://mcphub:smoke@smoke-db:5432/mcphub \
  -e NODE_ENV=production -e JWT_SECRET="$(openssl rand -hex 32)" \
  -e BETTER_AUTH_SECRET="$(openssl rand -hex 32)" -e ADMIN_PASSWORD=smoke-admin-pw \
  "$IMG" >/dev/null

for i in $(seq 1 90); do
  curl -fsS -o /dev/null http://127.0.0.1:$PORT/health && break
  [ "$i" = 90 ] && { echo "MCPHub did not become healthy"; exit 1; }
  sleep 2
done
echo "health ok"

got=$(docker exec smoke node -p 'require("/app/package.json").version')
[ "$got" = "$VERSION" ] || { echo "MCPHub version $got != $VERSION"; exit 1; }

docker exec smoke cat /etc/node-overlay
node=$(docker exec smoke node -v)
[ "$(printf '%s\n%s\n' "v$NODE" "$node" | sort -V | head -1)" = "v$NODE" ] || { echo "node $node older than v$NODE"; exit 1; }

# Database mode: the bootstrap admin is stored in Postgres and can log in
token=$(curl -fsS -X POST http://127.0.0.1:$PORT/api/auth/login -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"smoke-admin-pw"}' | jq -r .token)
[ -n "$token" ] && [ "$token" != null ] || { echo "admin login failed"; exit 1; }
[ "$(docker exec smoke-db psql -U mcphub -d mcphub -Atc 'select count(*) from users')" -ge 1 ] \
  || { echo "no users in database"; exit 1; }
echo "database mode ok"

# MCP endpoint demands a token and points to the OAuth metadata
hdr=$(curl -s -o /dev/null -D - -X POST http://127.0.0.1:$PORT/mcp -H 'Content-Type: application/json' -d '{}')
grep -q '^HTTP/1.1 401' <<<"$hdr" || { echo "/mcp did not answer 401"; exit 1; }
grep -qi '^www-authenticate: Bearer.*resource_metadata' <<<"$hdr" || { echo "/mcp without resource_metadata"; exit 1; }
curl -fsS http://127.0.0.1:$PORT/.well-known/oauth-authorization-server | jq -e .token_endpoint >/dev/null \
  || { echo "OAuth server metadata missing"; exit 1; }
echo "mcp auth ok"

if docker logs smoke 2>&1 | grep -E '\[FATAL\]|BetterAuthError'; then echo "fatal errors in log"; exit 1; fi
echo "MCPHub $got, node $node"
