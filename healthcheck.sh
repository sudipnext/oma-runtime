#!/bin/bash
set -euo pipefail
# A model key is deliberately not needed to check that the gateway is serving.
curl --fail --silent --max-time 3 "http://127.0.0.1:${AGENT37_GATEWAY_PORT:-3737}/v1/health" >/dev/null
