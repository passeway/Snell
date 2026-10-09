#!/usr/bin/env bash
set -euo pipefail

container_name="snell-check-${RANDOM}-$$"
trap 'docker rm -f "$container_name" >/dev/null 2>&1 || true' EXIT
docker build --build-arg "TEST_IMAGE=$TEST_IMAGE" -f tests/ci/Dockerfile -t snell-ci .

init=(/sbin/init)
if [[ "$TEST_IMAGE" == alpine:* ]]; then init=(sleep infinity); fi
docker run -d --name "$container_name" --privileged --cgroupns=private \
    --tmpfs /run --tmpfs /run/lock --tmpfs /tmp \
    --sysctl net.ipv6.conf.all.disable_ipv6=0 --sysctl net.ipv6.conf.default.disable_ipv6=0 \
    -v "$GITHUB_WORKSPACE:/repo:ro" -v "$RUNNER_TEMP/snell-cores:/core:ro" \
    -e SNELL_TEST_BINARY=/core/snell-server -e SING_BOX_TEST_BINARY=/core/sing-box \
    -e SNELL_SERVICE_TESTS=1 -w /repo snell-ci "${init[@]}"

if [[ "$TEST_IMAGE" == alpine:* ]]; then
    docker exec "$container_name" sh -ec 'mkdir -p /run/openrc; echo default > /run/openrc/softlevel'
else
    ready=0
    for ((attempt=0; attempt<30; attempt++)); do
        state=$(docker exec "$container_name" systemctl is-system-running 2>/dev/null || true)
        case "$state" in running|degraded) ready=1; break ;; esac
        sleep 1
    done
    if (( !ready )); then docker logs "$container_name"; exit 1; fi
fi

docker exec "$container_name" bash -ec '
    bash -n Snell.sh
    PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
'
