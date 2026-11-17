#!/bin/bash
# Real regression check: boot with an empty home, mutate state, and recreate.
set -euo pipefail
image="${1:?usage: smoke-test.sh IMAGE}"
container="oma-smoke-${RANDOM}"
volume="${container}-home"
cleanup() {
    docker logs "${container}" || true
    docker rm -f "${container}" >/dev/null 2>&1 || true
    docker volume rm "${volume}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

boot() {
    docker run -d --name "${container}" --memory=4g --cpus=2 \
        --mount "source=${volume},target=/home/node" "${image}" >/dev/null
    for _ in $(seq 1 90); do
        if [ "$(docker inspect -f '{{.State.Health.Status}}' "${container}")" = healthy ]; then
            return
        fi
        sleep 5
    done
    echo 'Container never became healthy' >&2
    return 1
}

wp() {
    docker exec "${container}" wp --path=/home/node/.oma/wordpress "$@"
}

docker volume create "${volume}" >/dev/null
boot
test "$(docker exec "${container}" id -u)" = 1000
docker exec "${container}" hermes --version
wp core verify-checksums
test "$(wp option get blog_public)" = 0
# The test site is installed before the HTTP service is exposed.
docker exec "${container}" curl -fsS http://127.0.0.1:8081/wp-json/ >/dev/null
test "$(docker exec "${container}" curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8081/wp-config.php)" = 403
docker exec "${container}" bash -c 'mkdir -p ~/.oma/wordpress/wp-content/uploads; printf "<?php echo 123;" > ~/.oma/wordpress/wp-content/uploads/blocked.php'
test "$(docker exec "${container}" curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8081/wp-content/uploads/blocked.php)" = 403

credentials_before="$(docker exec "${container}" sha256sum /home/node/.oma/wordpress-credentials.json)"
wp option update oma_smoke_marker persisted
post_id="$(wp post create --post_title='OMA persisted post' --post_status=publish --porcelain)"
docker exec "${container}" bash -c 'mkdir -p ~/.hermes/skills/oma-smoke; echo persistent-skill > ~/.hermes/skills/oma-smoke/SKILL.md'

# Graceful shutdown must flush the database before replacing the container.
docker stop --time 90 "${container}" >/dev/null
test "$(docker inspect -f '{{.State.ExitCode}}' "${container}")" = 0
docker rm "${container}" >/dev/null
boot
test "$(wp option get oma_smoke_marker)" = persisted
test "$(wp post get "${post_id}" --field=post_title)" = 'OMA persisted post'
test "$(docker exec "${container}" cat /home/node/.hermes/skills/oma-smoke/SKILL.md)" = persistent-skill
test "$(docker exec "${container}" sha256sum /home/node/.oma/wordpress-credentials.json)" = "${credentials_before}"
test "$(docker exec "${container}" stat -c %a /home/node/.oma/wordpress-credentials.json)" = 600
docker exec "${container}" curl -fsS http://127.0.0.1:8081/oma-persisted-post/ >/dev/null
docker stats --no-stream "${container}"
echo 'Passed: empty-home boot, gateway, WordPress, access controls, and persistence after recreation.'
