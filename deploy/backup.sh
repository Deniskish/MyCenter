#!/usr/bin/env bash
set -Eeuo pipefail

ENV_FILE="${MYCENTER_ENV_FILE:-/opt/mycenter/deploy/.env}"
LOCK_FILE="/run/lock/mycenter-operation.lock"
BACKUP_RESTART_MARKER="/run/mycenter-backup-restart-needed"
BACKUP_WORKER_NAME="mycenter-backup-worker"
was_running=0
restarted=0
leave_stopped="${MYCENTER_BACKUP_LEAVE_STOPPED:-0}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ "${EUID}" -eq 0 ]] || die "run this script as root"
[[ "${leave_stopped}" =~ ^(0|1)$ ]] || die "MYCENTER_BACKUP_LEAVE_STOPPED must be 0 or 1"
[[ -f "${ENV_FILE}" ]] || die "missing ${ENV_FILE}"
[[ "$(stat -c '%a' "${ENV_FILE}")" == "600" ]] || die "${ENV_FILE} must have mode 600"
[[ "$(stat -c '%u' "${ENV_FILE}")" == "0" ]] || die "${ENV_FILE} must be owned by root"

if [[ "${MYCENTER_OPERATION_LOCK_HELD:-0}" != "1" ]]; then
  exec 9>"${LOCK_FILE}"
  flock -n 9 || die "another MyCenter maintenance operation is already running"
else
  inherited_lock="$(readlink -f "/proc/$$/fd/9" 2>/dev/null || true)"
  [[ "${inherited_lock}" == "${LOCK_FILE}" ]] \
    || die "invalid inherited MyCenter maintenance lock"
  flock -n 9 || die "the inherited MyCenter maintenance lock is not held"
fi
if [[ "${leave_stopped}" -eq 1 && "${MYCENTER_OPERATION_LOCK_HELD:-0}" != "1" ]]; then
  die "leave-stopped backup mode requires the inherited maintenance lock"
fi

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

MYCENTER_SOURCE_DIR="${MYCENTER_SOURCE_DIR:-/opt/mycenter/src}"
MYCENTER_DEPLOY_DIR="${MYCENTER_DEPLOY_DIR:-/opt/mycenter/deploy}"
MYCENTER_STATE_DIR="${MYCENTER_STATE_DIR:-/opt/mycenter/state}"
MYCENTER_CONFIG_PATH="${MYCENTER_CONFIG_PATH:-${MYCENTER_DEPLOY_DIR}/config.json}"
MYCENTER_DEPLOYED_COMPOSE_PATH="${MYCENTER_DEPLOY_DIR}/docker-compose.yml"
MYCENTER_TOOLS_LINK="${MYCENTER_DEPLOY_DIR}/current-tools"
MAINTENANCE_MARKER="${MYCENTER_STATE_DIR}/maintenance-incomplete"
export MYCENTER_SOURCE_DIR MYCENTER_DEPLOY_DIR MYCENTER_STATE_DIR MYCENTER_CONFIG_PATH
install -d -o root -g root -m 0750 "${MYCENTER_STATE_DIR}"
[[ ! -e "${MAINTENANCE_MARKER}" ]] \
  || die "incomplete destructive maintenance blocks backup"
[[ ! -e "${BACKUP_RESTART_MARKER}" ]] \
  || die "an interrupted backup requires recovery before another maintenance action"
if docker container inspect "${BACKUP_WORKER_NAME}" >/dev/null 2>&1; then
  die "a stale backup helper container requires recovery"
fi

[[ "${MYCENTER_IMAGE_TAG:-}" =~ ^[0-9a-f]{7,40}$ ]] || die "MYCENTER_IMAGE_TAG is not versioned"
[[ "${MYCENTER_BOOTSTRAP_ACTIVE:-true}" == "false" ]] \
  || die "close the first-account bootstrap before creating backups"
[[ "${MYCENTER_NEW_ACCOUNTS:-true}" == "false" ]] \
  || die "public registration must remain disabled before creating backups"
[[ "${MYCENTER_REGISTRATION_TOKEN:-}" =~ ^[0-9a-f]{64}$ ]] \
  || die "the permanent registration guard is missing"
[[ -f "${MYCENTER_CONFIG_PATH}" ]] || die "missing runtime config"
[[ -f "${MYCENTER_DEPLOYED_COMPOSE_PATH}" ]] || die "missing deployed Compose definition"
[[ -f "${MYCENTER_DEPLOY_DIR}/config.production.template.json" ]] \
  || die "missing deployed config template"
jq --exit-status \
  '.domains[""].newAccounts == false
    and .domains[""].newAccountsPass == env.MYCENTER_REGISTRATION_TOKEN' \
  "${MYCENTER_CONFIG_PATH}" >/dev/null \
  || die "runtime registration policy does not match the closed permanent guard"
[[ -s "${MYCENTER_STATE_DIR}/current-image-tag" ]] \
  || die "the current image-tag record is missing"
current_tag="$(tr -d '\r\n' < "${MYCENTER_STATE_DIR}/current-image-tag")"
[[ "${current_tag}" == "${MYCENTER_IMAGE_TAG}" ]] \
  || die "the runtime image tag differs from the deployed tag record"
current_release_dir="${MYCENTER_STATE_DIR}/releases/${current_tag}"
[[ -s "${current_release_dir}/docker-compose.yml" \
  && -s "${current_release_dir}/config.production.template.json" \
  && -s "${current_release_dir}/config.json" \
  && -x "${current_release_dir}/tools/backup.sh" \
  && -x "${current_release_dir}/tools/backup-recover.sh" \
  && -x "${current_release_dir}/tools/deploy.sh" \
  && -x "${current_release_dir}/tools/healthcheck.sh" \
  && -x "${current_release_dir}/tools/restore.sh" \
  && -x "${current_release_dir}/tools/update.sh" ]] \
  || die "the current release snapshot is incomplete"
[[ "$(readlink -f "${MYCENTER_TOOLS_LINK}" 2>/dev/null || true)" \
  == "$(readlink -f "${current_release_dir}/tools")" ]] \
  || die "the active maintenance tools do not match the current release"
cmp -s "${current_release_dir}/docker-compose.yml" "${MYCENTER_DEPLOYED_COMPOSE_PATH}" \
  || die "the deployed Compose definition differs from the release snapshot"
cmp -s "${current_release_dir}/config.production.template.json" \
  "${MYCENTER_DEPLOY_DIR}/config.production.template.json" \
  || die "the deployed config template differs from the release snapshot"
cmp -s "${current_release_dir}/config.json" "${MYCENTER_CONFIG_PATH}" \
  || die "the runtime config differs from the release snapshot"

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
    fi
    sleep 5
  done
  return 1
}

mark_backup_restart_needed() {
  local tmp
  tmp="$(mktemp /run/mycenter-backup-restart-needed.tmp.XXXXXX)" || return 1
  if ! printf '%s\n' "$$" > "${tmp}" || ! chown root:root "${tmp}" \
    || ! chmod 0600 "${tmp}"; then
    rm -f -- "${tmp}"
    return 1
  fi
  mv -f -- "${tmp}" "${BACKUP_RESTART_MARKER}" || {
    rm -f -- "${tmp}"
    return 1
  }
}

restart_on_error() {
  local exit_code=$? recovery_status=0
  [[ "${exit_code}" -ne 0 ]] || exit_code=1
  trap - EXIT INT TERM
  if [[ "${was_running}" -eq 1 && "${restarted}" -eq 0 ]]; then
    echo "Restarting MyCenter after an interrupted backup..." >&2
    if compose up -d --no-build mycenter >/dev/null && wait_for_health; then
      restarted=1
      rm -f -- "${BACKUP_RESTART_MARKER}"
    else
      recovery_status=1
      echo "CRITICAL: MyCenter did not recover after the backup failure." >&2
    fi
  fi
  [[ "${recovery_status}" -eq 0 ]] \
    || echo "The original backup error is preserved; manual service recovery is required." >&2
  exit "${exit_code}"
}
trap restart_on_error EXIT INT TERM

cid="$(compose ps -a -q mycenter 2>/dev/null || true)"
[[ -n "${cid}" ]] || die "the MyCenter container does not exist"
docker image inspect "mycenter:${MYCENTER_IMAGE_TAG}" >/dev/null 2>&1 \
  || die "the configured backup helper image is missing"
compose config --quiet || die "the Compose configuration is invalid"
for required_volume in meshcentral-data meshcentral-files meshcentral-web meshcentral-backups; do
  docker volume inspect "${required_volume}" >/dev/null 2>&1 \
    || die "required Docker volume is missing: ${required_volume}"
done
configured_image="$(docker inspect --format '{{.Config.Image}}' "${cid}" 2>/dev/null || true)"
[[ "${configured_image}" == "mycenter:${MYCENTER_IMAGE_TAG}" ]] \
  || die "the container image does not match MYCENTER_IMAGE_TAG"
if [[ -n "${cid}" && "$(docker inspect --format '{{.State.Running}}' "${cid}" 2>/dev/null || true)" == "true" ]]; then
  was_running=1
  [[ "$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "${cid}" 2>/dev/null || true)" \
    == "unless-stopped" ]] || die "MyCenter restart policy is not unless-stopped"
  wait_for_health || die "MyCenter must be healthy before a consistent backup"
  if [[ "${leave_stopped}" -eq 0 ]]; then
    mark_backup_restart_needed || die "unable to arm interrupted-backup recovery"
  fi
  compose stop --timeout 45 mycenter
fi

timestamp="$(date -u +%Y-%m-%dT%H%M%SZ)"
backup_name="mycenter-${timestamp}.tar.gz"
weekly_due=0
weekly_period=""
if [[ "$(date +%u)" == "7" ]]; then
  weekly_due=1
  weekly_period="$(date +%G-%V)"
fi

docker run --rm --name "${BACKUP_WORKER_NAME}" \
  --network none \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,nodev,mode=1777,size=64m \
  --user 0:0 \
  --cap-drop ALL \
  --cap-add DAC_OVERRIDE \
  --cap-add DAC_READ_SEARCH \
  --security-opt no-new-privileges:true \
  --env "BACKUP_NAME=${backup_name}" \
  --env "WEEKLY_DUE=${weekly_due}" \
  --env "WEEKLY_PERIOD=${weekly_period}" \
  --volume meshcentral-data:/snapshot/data:ro \
  --volume meshcentral-files:/snapshot/files:ro \
  --volume meshcentral-web:/snapshot/web:ro \
  --volume meshcentral-backups:/backups \
  --volume "${MYCENTER_CONFIG_PATH}:/snapshot/deployment/config.json:ro" \
  --volume "${ENV_FILE}:/snapshot/deployment/.env:ro" \
  --volume "${MYCENTER_DEPLOYED_COMPOSE_PATH}:/snapshot/deployment/docker-compose.yml:ro" \
  --volume "${MYCENTER_DEPLOY_DIR}/config.production.template.json:/snapshot/deployment/config.production.template.json:ro" \
  --volume "${MYCENTER_STATE_DIR}:/snapshot/state:ro" \
  --entrypoint /bin/sh \
  "mycenter:${MYCENTER_IMAGE_TAG}" \
  -c '
    set -eu
    umask 077
    install -d -m 0700 /backups/daily /backups/weekly
    temp_archive="/backups/daily/.${BACKUP_NAME}.tmp"
    final_archive="/backups/daily/${BACKUP_NAME}"
    checksum_path="${final_archive}.sha256"
    weekly_temp=""
    weekly_checksum_temp=""
    weekly_final_created=""
    weekly_checksum_created=""
    backup_complete=0
    cleanup_partial_backup() {
      if [ "${backup_complete}" -ne 1 ]; then
        rm -f -- "${temp_archive}" "${final_archive}" "${checksum_path}"
        [ -z "${weekly_temp}" ] || rm -f -- "${weekly_temp}"
        [ -z "${weekly_checksum_temp}" ] || rm -f -- "${weekly_checksum_temp}"
        [ -z "${weekly_final_created}" ] || rm -f -- "${weekly_final_created}"
        [ -z "${weekly_checksum_created}" ] || rm -f -- "${weekly_checksum_created}"
      fi
    }
    trap cleanup_partial_backup EXIT INT TERM
    test ! -e "${final_archive}" && test ! -e "${checksum_path}" || {
      echo "backup timestamp collision" >&2
      exit 1
    }
    rm -f -- "${temp_archive}"
    tar --numeric-owner -C /snapshot -czf "${temp_archive}" data files web deployment state
    chmod 0600 "${temp_archive}"
    mv -f -- "${temp_archive}" "${final_archive}"
    (cd /backups/daily && sha256sum "${BACKUP_NAME}" > "${BACKUP_NAME}.sha256")

    if [ "${WEEKLY_DUE}" = "1" ]; then
      weekly_name="mycenter-week-${WEEKLY_PERIOD}.tar.gz"
      weekly_final="/backups/weekly/${weekly_name}"
      weekly_checksum="${weekly_final}.sha256"
      if { [ -e "${weekly_final}" ] && [ ! -e "${weekly_checksum}" ]; } \
        || { [ ! -e "${weekly_final}" ] && [ -e "${weekly_checksum}" ]; }; then
        echo "incomplete existing weekly backup pair" >&2
        exit 1
      fi
      if [ ! -e "${weekly_final}" ] && [ ! -e "${weekly_checksum}" ]; then
        weekly_temp="/backups/weekly/.${weekly_name}.${BACKUP_NAME}.tmp"
        weekly_checksum_temp="${weekly_temp}.sha256"
        cp --reflink=auto "${final_archive}" "${weekly_temp}" 2>/dev/null \
          || cp "${final_archive}" "${weekly_temp}"
        chmod 0600 "${weekly_temp}"
        weekly_hash="$(sha256sum "${weekly_temp}")"
        weekly_hash="${weekly_hash%% *}"
        printf "%s  %s\n" "${weekly_hash}" "${weekly_name}" > "${weekly_checksum_temp}"
        chmod 0600 "${weekly_checksum_temp}"
        mv -f -- "${weekly_temp}" "${weekly_final}"
        weekly_final_created="${weekly_final}"
        weekly_temp=""
        mv -f -- "${weekly_checksum_temp}" "${weekly_checksum}"
        weekly_checksum_created="${weekly_checksum}"
        weekly_checksum_temp=""
      fi
    fi

    find /backups/daily -maxdepth 1 -type f -name "mycenter-*.tar.gz" -printf "%f\n" \
      | sort -r | awk "NR > 7" \
      | while IFS= read -r expired; do
          rm -f -- "/backups/daily/${expired}" "/backups/daily/${expired}.sha256"
        done
    find /backups/weekly -maxdepth 1 -type f -name "mycenter-week-*.tar.gz" -printf "%f\n" \
      | sort -r | awk "NR > 4" \
      | while IFS= read -r expired; do
          rm -f -- "/backups/weekly/${expired}" "/backups/weekly/${expired}.sha256"
        done
    backup_complete=1
    trap - EXIT INT TERM
  '

if [[ "${was_running}" -eq 1 ]]; then
  if [[ "${leave_stopped}" -eq 1 ]]; then
    restarted=1
  elif compose up -d --no-build mycenter && wait_for_health; then
    restarted=1
    rm -f -- "${BACKUP_RESTART_MARKER}"
  else
    die "backup succeeded, but MyCenter did not become healthy after restart"
  fi
fi

trap - EXIT INT TERM
echo "Backup created: daily/${backup_name}"
if [[ "${was_running}" -eq 1 && "${leave_stopped}" -eq 1 ]]; then
  echo "MyCenter remains stopped for the locked maintenance operation."
fi
