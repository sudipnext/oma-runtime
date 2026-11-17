#!/bin/bash
# Boot a general-purpose runtime, then verify home persistence with VM-style pipes.
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
    local args=(run -d --name "${container}" --memory=4g --cpus=2
        --mount "source=${volume},target=/home/node")
    if [[ "${1:-}" == vm-pipes ]]; then
        # Agent37 creates output pipes as root before dropping to the image user.
        args+=(--user root --entrypoint /usr/bin/setpriv "${image}"
            --reuid=1000 --regid=1000 --init-groups /usr/local/bin/entrypoint.sh)
    else
        args+=("${image}")
    fi
    docker "${args[@]}" >/dev/null
    for _ in $(seq 1 60); do
        if [ "$(docker inspect -f '{{.State.Health.Status}}' "${container}")" = healthy ]; then
            return
        fi
        sleep 5
    done
    echo 'Container never became healthy' >&2
    return 1
}

docker volume create "${volume}" >/dev/null
boot
test "$(docker exec --user node "${container}" id -u)" = 1000
docker exec --user node "${container}" hermes --version
docker exec --user node "${container}" bash -c 'command -v python3 uv node npm git curl sudo >/dev/null; test ! -d /opt/oma/wordpress; test ! -d "$HOME/.oma/wordpress"; ! command -v mariadbd'
docker exec --user node "${container}" bash -c 'mkdir -p ~/.hermes/skills/oma-smoke; echo persistent-skill > ~/.hermes/skills/oma-smoke/SKILL.md; echo persistent-state > ~/oma-smoke-state'

docker stop --time 90 "${container}" >/dev/null
exit_code="$(docker inspect -f '{{.State.ExitCode}}' "${container}")"
[[ "${exit_code}" == 0 || "${exit_code}" == 143 ]]
docker rm "${container}" >/dev/null
boot vm-pipes
test "$(docker exec --user node "${container}" cat /home/node/.hermes/skills/oma-smoke/SKILL.md)" = persistent-skill
test "$(docker exec --user node "${container}" cat /home/node/oma-smoke-state)" = persistent-state
docker stats --no-stream "${container}"
echo 'Passed: general tools, no bundled CMS/database, gateway, VM-style output pipes, and persistent home.'
