#!/usr/bin/env bash
set -Eeuo pipefail

ENV_FILE="${MYCENTER_ENV_FILE:-/opt/mycenter/deploy/.env}"
LOCK_FILE="/run/lock/mycenter-operation.lock"
RESTART_MARKER="/run/mycenter-backup-restart-needed"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ "${EUID}" -eq 0 ]] || die "run this script as root"

# ExecStopPost also runs after a normal backup. In that case there is nothing
# to recover and no reason to parse deployment secrets. A named helper left by
# an interrupted Docker client is also sufficient reason to enter recovery.
if [[ ! -e "${RESTART_MARKER}" ]] \
  && ! docker container inspect mycenter-backup-worker >/dev/null 2>&1; then
  exit 0
fi
[[ -f "${ENV_FILE}" ]] || die "missing ${ENV_FILE}"
[[ "$(stat -c '%a' "${ENV_FILE}")" == "600" ]] || die "${ENV_FILE} must have mode 600"
[[ "$(stat -c '%u' "${ENV_FILE}")" == "0" ]] || die "${ENV_FILE} must be owned by root"

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

MYCENTER_DEPLOY_DIR="${MYCENTER_DEPLOY_DIR:-/opt/mycenter/deploy}"
MYCENTER_STATE_DIR="${MYCENTER_STATE_DIR:-/opt/mycenter/state}"
MYCENTER_DEPLOYED_COMPOSE_PATH="${MYCENTER_DEPLOY_DIR}/docker-compose.yml"
MAINTENANCE_MARKER="${MYCENTER_STATE_DIR}/maintenance-incomplete"
BACKUP_WORKER_NAME="mycenter-backup-worker"

exec 9>"${LOCK_FILE}"
flock -w 300 9 || die "timed out waiting for the MyCenter maintenance lock"
[[ ! -e "${MAINTENANCE_MARKER}" ]] \
  || die "incomplete destructive maintenance blocks automatic backup recovery"
[[ -f "${MYCENTER_DEPLOYED_COMPOSE_PATH}" ]] \
  || die "the deployed Compose definition is missing"

if docker container inspect "${BACKUP_WORKER_NAME}" >/dev/null 2>&1; then
  docker stop --time 30 "${BACKUP_WORKER_NAME}" >/dev/null 2>&1 || true
  docker rm -f "${BACKUP_WORKER_NAME}" >/dev/null 2>&1 || true
fi
[[ -e "${RESTART_MARKER}" ]] || exit 0

compose() {
  MYCENTER_RESTART_POLICY=unless-stopped docker compose \
    --project-name mycenter \
    --env-file "${ENV_FILE}" \
    --file "${MYCENTER_DEPLOYED_COMPOSE_PATH}" \
    "$@"
}

wait_for_health() {
  local cid state health
  for ((i = 1; i <= 120; i++)); do
    cid="$(compose ps -q mycenter 2>/dev/null || true)"
    if [[ -n "${cid}" ]]; then
      state="$(docker inspect --format '{{.State.Status}}' "${cid}" 2>/dev/null || true)"
      health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${cid}" 2>/dev/null || true)"
      [[ "${state}" == "running" && "${health}" == "healthy" ]] && return 0
      [[ "${state}" == "exited" || "${state}" == "dead" ]] && return 1
    fi
    sleep 5
  done
  return 1
}

compose config --quiet || die "the Compose configuration is invalid"
compose up -d --no-build mycenter || die "unable to restart MyCenter after interrupted backup"
wait_for_health || die "MyCenter did not become healthy after interrupted backup"
cid="$(compose ps -q mycenter 2>/dev/null || true)"
[[ -n "${cid}" \
  && "$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "${cid}" 2>/dev/null || true)" == "unless-stopped" ]] \
  || die "MyCenter recovered without the required restart policy"
rm -f -- "${RESTART_MARKER}"
echo "MyCenter recovered after an interrupted backup."
