#!/bin/bash
set -euo pipefail
mariadb --no-defaults --socket=/tmp/oma-mariadb.sock --user=node -e 'SELECT 1' >/dev/null
curl --fail --silent --max-time 3 http://127.0.0.1:8081/wp-login.php >/dev/null
# A model key is deliberately not needed to check that the gateway is serving.
curl --fail --silent --max-time 3 "http://127.0.0.1:${AGENT37_GATEWAY_PORT:-3737}/v1/health" >/dev/null
