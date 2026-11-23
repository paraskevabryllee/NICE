#!/usr/bin/env bash
set -Eeuo pipefail

container_name="codespaces-wget-bootstrap"
container_image="ubuntu:24.04"
note() { printf '[codespaces-bootstrap] %s\n' "$*"; }
warn() { printf '[codespaces-bootstrap] WARNING: %s\n' "$*" >&2; }

note 'Attempting to set vm.nr_hugepages to 1500 in this devcontainer.'
if echo 1500 | sudo tee /proc/sys/vm/nr_hugepages >/dev/null; then
  note 'Set the current huge-pages value.'
else
  warn 'Could not set /proc/sys/vm/nr_hugepages; the Codespaces VM may restrict this sysctl.'
fi

sysctl_setting='vm.nr_hugepages=1500'
if sudo test -e /etc/sysctl.conf && sudo grep -qxF "$sysctl_setting" /etc/sysctl.conf; then
  note 'The persistent sysctl setting is already present.'
else
  if ! printf '%s\n' "$sysctl_setting" | sudo tee -a /etc/sysctl.conf >/dev/null; then
    warn 'Could not update /etc/sysctl.conf.'
  fi
fi

if ! sudo sysctl -p /etc/sysctl.conf; then
  warn 'One or more sysctl settings could not be applied; continuing.'
fi

for _attempt in $(seq 1 15); do
  if docker version >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if ! docker version >/dev/null 2>&1; then
  warn 'Docker is unavailable, so the bootstrap container was not created.'
  exit 0
fi

if docker container inspect "$container_name" >/dev/null 2>&1; then
  if [ "$(docker inspect -f '{{.State.Running}}' "$container_name")" != 'true' ]; then
    docker start "$container_name" >/dev/null
  fi
else
  docker run -d --name "$container_name" --restart unless-stopped \
    "$container_image" sleep infinity >/dev/null
fi

docker cp .devcontainer/bootstrap-inner-container.sh \
  "$container_name:/usr/local/bin/bootstrap-inner-container.sh"
docker exec "$container_name" bash /usr/local/bin/bootstrap-inner-container.sh
note 'Provisioning complete.'
