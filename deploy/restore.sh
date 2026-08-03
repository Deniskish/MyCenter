#!/usr/bin/env bash
set -Eeuo pipefail

ENV_FILE="${MYCENTER_ENV_FILE:-/opt/mycenter/deploy/.env}"
LOCK_FILE="/run/lock/mycenter-operation.lock"
MODE="dry-run"
ARCHIVE_REF=""
CONFIRMATION=""
DRYRUN_DIR=""
RECOVER_INCOMPLETE=0

die() {
  echo "ERROR: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  restore.sh [--dry-run] [daily/ARCHIVE.tar.gz]
  restore.sh --apply daily/ARCHIVE.tar.gz --confirm APPLY
  restore.sh --recover-incomplete daily/ARCHIVE.tar.gz --confirm RECOVER_INCOMPLETE

Without --apply, this script only validates and extracts into a temporary
directory. Production volumes are not modified.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      MODE="dry-run"
      shift
      ;;
    --apply)
      MODE="apply"
      shift
      ;;
    --recover-incomplete)
      MODE="apply"
      RECOVER_INCOMPLETE=1
      shift
      ;;
    --confirm)
      [[ $# -ge 2 ]] || die "--confirm requires a value"
      CONFIRMATION="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      [[ -z "${ARCHIVE_REF}" ]] || die "only one archive may be selected"
      ARCHIVE_REF="$1"
      shift
      ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || die "run this script as root"
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

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

MYCENTER_SOURCE_DIR="${MYCENTER_SOURCE_DIR:-/opt/mycenter/src}"
MYCENTER_DEPLOY_DIR="${MYCENTER_DEPLOY_DIR:-/opt/mycenter/deploy}"
MYCENTER_STATE_DIR="${MYCENTER_STATE_DIR:-/opt/mycenter/state}"
MYCENTER_CONFIG_PATH="${MYCENTER_CONFIG_PATH:-${MYCENTER_DEPLOY_DIR}/config.json}"
MYCENTER_DEPLOYED_COMPOSE_PATH="${MYCENTER_DEPLOY_DIR}/docker-compose.yml"
MYCENTER_DEPLOYED_TEMPLATE_PATH="${MYCENTER_DEPLOY_DIR}/config.production.template.json"
MYCENTER_TOOLS_LINK="${MYCENTER_DEPLOY_DIR}/current-tools"
MAINTENANCE_MARKER="${MYCENTER_STATE_DIR}/maintenance-incomplete"
BACKUP_RESTART_MARKER="/run/mycenter-backup-restart-needed"
RESTORE_TMP_ROOT="/opt/mycenter/restore-tmp"
export MYCENTER_SOURCE_DIR MYCENTER_DEPLOY_DIR MYCENTER_STATE_DIR MYCENTER_CONFIG_PATH

[[ "${MYCENTER_IMAGE_TAG:-}" =~ ^[0-9a-f]{7,40}$ ]] || die "MYCENTER_IMAGE_TAG is not versioned"
[[ -f "${MYCENTER_DEPLOYED_COMPOSE_PATH}" ]] || die "the deployed Compose definition is missing"
[[ -f "${MYCENTER_DEPLOYED_TEMPLATE_PATH}" ]] || die "the deployed config template is missing"
install -d -o root -g root -m 0750 "${MYCENTER_STATE_DIR}"
install -d -o root -g root -m 0700 "${RESTORE_TMP_ROOT}"
if [[ "${RECOVER_INCOMPLETE}" -eq 1 ]]; then
  [[ -f "${MAINTENANCE_MARKER}" \
    && "$(tr -d '\r\n' < "${MAINTENANCE_MARKER}")" == "restore" ]] \
    || die "there is no interrupted data restore to recover"
else
  [[ ! -e "${MAINTENANCE_MARKER}" ]] \
    || die "incomplete destructive maintenance requires an explicit recovery action"
fi
[[ ! -e "${BACKUP_RESTART_MARKER}" ]] \
  || die "an interrupted backup requires recovery before restore"
if docker container inspect mycenter-backup-worker >/dev/null 2>&1; then
  die "a stale backup helper container requires recovery"
fi

compose() {
  MYCENTER_RESTART_POLICY=unless-stopped docker compose \
    --project-name mycenter \
    --env-file "${ENV_FILE}" \
    --file "${MYCENTER_DEPLOYED_COMPOSE_PATH}" \
    "$@"
}

compose_unverified() {
  MYCENTER_RESTART_POLICY=no docker compose \
    --project-name mycenter \
    --env-file "${ENV_FILE}" \
    --file "${MYCENTER_DEPLOYED_COMPOSE_PATH}" \
    "$@"
}

docker image inspect "mycenter:${MYCENTER_IMAGE_TAG}" >/dev/null 2>&1 \
  || die "the configured restore helper image is missing"
for required_volume in meshcentral-data meshcentral-files meshcentral-web meshcentral-backups; do
  docker volume inspect "${required_volume}" >/dev/null 2>&1 \
    || die "required Docker volume is missing: ${required_volume}"
done
compose config --quiet || die "the Compose configuration is invalid"
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
  || die "the deployed Compose definition differs from the current release"
cmp -s "${current_release_dir}/config.production.template.json" \
  "${MYCENTER_DEPLOYED_TEMPLATE_PATH}" \
  || die "the deployed config template differs from the current release"
if [[ "${RECOVER_INCOMPLETE}" -eq 0 ]]; then
  cmp -s "${current_release_dir}/config.json" "${MYCENTER_CONFIG_PATH}" \
    || die "the runtime config differs from the current release"
fi

set_env_value() {
  local key="$1" value="$2" tmp
  [[ "${key}" =~ ^[A-Z0-9_]+$ ]] || die "invalid environment key"
  [[ "${value}" != *$'\n'* && "${value}" != *$'\r'* ]] || die "invalid environment value"
  tmp="$(mktemp "${ENV_FILE}.tmp.XXXXXX")" || return 1
  if ! awk -v key="${key}" '
    $0 !~ ("^" key "=") { print }
  ' "${ENV_FILE}" > "${tmp}"; then
    rm -f -- "${tmp}"
    return 1
  fi
  if ! printf '%s=%s\n' "${key}" "${value}" >> "${tmp}"; then
    rm -f -- "${tmp}"
    return 1
  fi
  if ! chown root:root "${tmp}" || ! chmod 0600 "${tmp}"; then
    rm -f -- "${tmp}"
    return 1
  fi
  mv -f -- "${tmp}" "${ENV_FILE}" || {
    rm -f -- "${tmp}"
    return 1
  }
}

install_config_file() {
  local source_path="$1" destination_path="${2:-${MYCENTER_CONFIG_PATH}}"
  local owner="${3:-10001}" group="${4:-10001}" tmp
  [[ -f "${source_path}" ]] || return 1
  tmp="$(mktemp "${destination_path}.tmp.XXXXXX")" || return 1
  if ! install -o "${owner}" -g "${group}" -m 0600 "${source_path}" "${tmp}"; then
    rm -f -- "${tmp}"
    return 1
  fi
  mv -f -- "${tmp}" "${destination_path}" || {
    rm -f -- "${tmp}"
    return 1
  }
}

update_runtime_session_key() {
  local tmp
  tmp="$(mktemp "${MYCENTER_CONFIG_PATH}.tmp.XXXXXX")" || return 1
  if ! jq '.settings.sessionKey = env.MYCENTER_SESSION_KEY' \
    "${MYCENTER_CONFIG_PATH}" > "${tmp}" \
    || ! jq empty "${tmp}" >/dev/null \
    || ! chown 10001:10001 "${tmp}" || ! chmod 0600 "${tmp}"; then
    rm -f -- "${tmp}"
    return 1
  fi
  mv -f -- "${tmp}" "${MYCENTER_CONFIG_PATH}" || {
    rm -f -- "${tmp}"
    return 1
  }
}

volume_metrics() {
  docker run --rm \
    --network none \
    --read-only \
    --user 0:0 \
    --cap-drop ALL \
    --cap-add DAC_READ_SEARCH \
    --security-opt no-new-privileges:true \
    --volume meshcentral-data:/target/data:ro \
    --volume meshcentral-files:/target/files:ro \
    --volume meshcentral-web:/target/web:ro \
    --entrypoint /bin/sh \
    "mycenter:${MYCENTER_IMAGE_TAG}" \
    -c '
      set -eu
      for name in data files web; do
        bytes="$(du -sb "/target/${name}" | awk "{ print \$1 }")"
        device="$(stat -c "%d" "/target/${name}")"
        available="$(df -P -B1 "/target/${name}" | awk "NR == 2 { print \$4 }")"
        printf "%s %s %s %s\n" "${name}" "${bytes}" "${device}" "${available}"
      done
    '
}

backup_available_bytes() {
  docker run --rm \
    --network none \
    --read-only \
    --user 0:0 \
    --cap-drop ALL \
    --security-opt no-new-privileges:true \
    --volume meshcentral-backups:/backups:ro \
    --entrypoint /bin/sh \
    "mycenter:${MYCENTER_IMAGE_TAG}" \
    -c 'df -P -B1 /backups | awk "NR == 2 { print \$4 }"'
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

verify_runtime_restart_disabled() {
  local cid policy
  cid="$(compose ps -q mycenter 2>/dev/null || true)"
  [[ -n "${cid}" ]] || return 1
  policy="$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "${cid}" 2>/dev/null || true)"
  [[ "${policy}" == "no" ]]
}

set_runtime_restart_policy() {
  local cid policy
  cid="$(compose ps -q mycenter 2>/dev/null || true)"
  [[ -n "${cid}" ]] || return 1
  docker update --restart=unless-stopped "${cid}" >/dev/null || return 1
  policy="$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "${cid}" 2>/dev/null || true)"
  [[ "${policy}" == "unless-stopped" ]]
}

stop_runtime_proven() {
  local running
  compose stop --timeout 45 mycenter >/dev/null 2>&1 || true
  if ! docker container inspect mycenter >/dev/null 2>&1; then
    return 0
  fi
  running="$(docker inspect --format '{{.State.Running}}' mycenter 2>/dev/null || true)"
  if [[ "${running}" == "true" ]]; then
    docker stop --time 45 mycenter >/dev/null 2>&1 || true
    running="$(docker inspect --format '{{.State.Running}}' mycenter 2>/dev/null || true)"
  fi
  [[ "${running}" == "false" ]]
}

mark_maintenance_incomplete() {
  local tmp
  tmp="$(mktemp "${MYCENTER_STATE_DIR}/maintenance-incomplete.tmp.XXXXXX")" || return 1
  if ! printf '%s\n' restore > "${tmp}" || ! chown root:root "${tmp}" \
    || ! chmod 0600 "${tmp}"; then
    rm -f -- "${tmp}"
    return 1
  fi
  mv -f -- "${tmp}" "${MAINTENANCE_MARKER}" || {
    rm -f -- "${tmp}"
    return 1
  }
}

runtime_stopped_for_restore=0
destructive_restore_started=0

restore_failure() {
  local exit_code=$? recovery_status=0 stop_status=0
  [[ "${exit_code}" -ne 0 ]] || exit_code=1
  trap - EXIT INT TERM
  set +e
  if [[ "${runtime_stopped_for_restore}" -eq 1 ]]; then
    if [[ "${destructive_restore_started}" -eq 1 || -e "${MAINTENANCE_MARKER}" ]]; then
      stop_runtime_proven || stop_status=1
      echo "The persistent maintenance marker was retained for manual recovery." >&2
      if [[ "${stop_status}" -eq 0 ]]; then
        echo "Restore failed after destructive maintenance began; MyCenter is stopped." >&2
      else
        echo "CRITICAL: MyCenter could not be proven stopped; inspect the exact container immediately." >&2
      fi
    else
      echo "Restore failed before volume replacement; restarting the unchanged runtime..." >&2
      if compose up -d --no-build mycenter >/dev/null && wait_for_health; then
        echo "The unchanged runtime was restored." >&2
      else
        recovery_status=1
        echo "CRITICAL: the unchanged runtime did not recover after restore preflight failure." >&2
      fi
    fi
  fi
  cleanup_dryrun
  [[ "${recovery_status}" -eq 0 ]] \
    || echo "Manual service recovery is required." >&2
  exit "${exit_code}"
}

cleanup_dryrun() {
  if [[ -n "${DRYRUN_DIR}" ]]; then
    case "${DRYRUN_DIR}" in
      "${RESTORE_TMP_ROOT}"/mycenter-restore-dryrun.*)
        rm -rf -- "${DRYRUN_DIR}"
        ;;
      *)
        echo "Refusing to remove unexpected temporary path: ${DRYRUN_DIR}" >&2
        ;;
    esac
  fi
}
trap cleanup_dryrun EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ "${RECOVER_INCOMPLETE}" -eq 1 && -z "${ARCHIVE_REF}" ]]; then
  die "interrupted restore recovery requires an explicit backup archive"
fi
if [[ -z "${ARCHIVE_REF}" ]]; then
  ARCHIVE_REF="$(docker run --rm \
    --network none \
    --read-only \
    --user 0:0 \
    --cap-drop ALL \
    --security-opt no-new-privileges:true \
    --volume meshcentral-backups:/backups:ro \
    --entrypoint /bin/sh \
    "mycenter:${MYCENTER_IMAGE_TAG}" \
    -c 'find /backups/daily -maxdepth 1 -type f -name "mycenter-*.tar.gz" -printf "%f\n" | sort | tail -n 1 | sed "s#^#daily/#"')"
fi

[[ "${ARCHIVE_REF}" =~ ^(daily/mycenter-[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{6}Z\.tar\.gz|weekly/mycenter-week-[0-9]{4}-[0-9]{2}\.tar\.gz)$ ]] \
  || die "invalid or missing archive reference"

archive_kind="${ARCHIVE_REF%%/*}"
archive_name="${ARCHIVE_REF#*/}"
if find "${RESTORE_TMP_ROOT}" -maxdepth 1 -type d -name 'mycenter-restore-dryrun.*' -print -quit \
  | grep -q .; then
  die "a stale restore dry-run directory exists; inspect it before retrying"
fi
DRYRUN_DIR="$(mktemp -d "${RESTORE_TMP_ROOT}/mycenter-restore-dryrun.XXXXXX")"
chmod 0700 "${DRYRUN_DIR}"

docker run --rm \
  --network none \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,nodev,mode=1777,size=64m \
  --user 0:0 \
  --cap-drop ALL \
  --cap-add DAC_OVERRIDE \
  --cap-add DAC_READ_SEARCH \
  --security-opt no-new-privileges:true \
  --env "ARCHIVE_KIND=${archive_kind}" \
  --env "ARCHIVE_NAME=${archive_name}" \
  --volume meshcentral-backups:/backups:ro \
  --volume "${DRYRUN_DIR}:/restore" \
  --entrypoint /bin/sh \
  "mycenter:${MYCENTER_IMAGE_TAG}" \
  -c '
    set -eu
    archive_dir="/backups/${ARCHIVE_KIND}"
    archive_path="${archive_dir}/${ARCHIVE_NAME}"
    test -s "${archive_path}"
    test -s "${archive_path}.sha256"
    (cd "${archive_dir}" && sha256sum -c "${ARCHIVE_NAME}.sha256")
    tar -tzf "${archive_path}" > /tmp/archive-list
    awk '\''
      /^\// { bad = 1 }
      {
        count = split($0, part, "/")
        for (i = 1; i <= count; i++) if (part[i] == "..") bad = 1
      }
      END { exit bad }
    '\'' /tmp/archive-list
    required_bytes="$(tar -tvzf "${archive_path}" | awk '\''{ total += $3 } END { print total + 0 }'\'')"
    available_bytes="$(df -P -B1 /restore | awk '\''NR == 2 { print $4 }'\'')"
    test "${available_bytes}" -gt "$((required_bytes + 67108864))" || {
      echo "insufficient temporary space for restore dry-run" >&2
      exit 1
    }
    tar --no-same-owner -xzf "${archive_path}" -C /restore
    test -d /restore/data
    test -d /restore/files
    test -d /restore/web
    test -d /restore/deployment
    test -s /restore/deployment/config.json
    test -s /restore/deployment/docker-compose.yml
    test -s /restore/deployment/config.production.template.json
    node -e '\''JSON.parse(require("fs").readFileSync("/restore/deployment/config.json", "utf8"))'\''
  '

restored_domain="$(jq -r '.settings.cert // empty' "${DRYRUN_DIR}/deployment/config.json")"
restored_session_key="$(jq -r '.settings.sessionKey // empty' "${DRYRUN_DIR}/deployment/config.json")"
[[ "${restored_domain}" == "${MYCENTER_DOMAIN}" ]] || die "backup belongs to a different domain"
[[ "${restored_session_key}" =~ ^[0-9a-f]{96}$ ]] || die "restored session key is invalid"

echo "Restore dry-run PASS: ${ARCHIVE_REF}"
echo "Checksum, archive paths, JSON, domain and required directories were validated."

if [[ "${MODE}" == "dry-run" ]]; then
  exit 0
fi

if [[ "${RECOVER_INCOMPLETE}" -eq 1 ]]; then
  [[ "${CONFIRMATION}" == "RECOVER_INCOMPLETE" ]] \
    || die "interrupted restore recovery requires --confirm RECOVER_INCOMPLETE"
else
  [[ "${CONFIRMATION}" == "APPLY" ]] \
    || die "destructive restore requires --confirm APPLY"
fi
[[ "${MYCENTER_BOOTSTRAP_ACTIVE:-true}" == "false" ]] \
  || die "close the first-account bootstrap before applying a restore"
[[ "${MYCENTER_NEW_ACCOUNTS:-true}" == "false" ]] \
  || die "public registration must remain disabled while applying a restore"
[[ "${MYCENTER_REGISTRATION_TOKEN:-}" =~ ^[0-9a-f]{64}$ ]] \
  || die "the permanent registration guard is invalid"
MYCENTER_REGISTRATION_TOKEN="${MYCENTER_REGISTRATION_TOKEN}" jq --exit-status \
  '.domains[""].newAccounts == false
    and .domains[""].newAccountsPass == env.MYCENTER_REGISTRATION_TOKEN' \
  "${MYCENTER_CONFIG_PATH}" >/dev/null \
  || die "runtime registration policy does not match the permanent guard"

if [[ "${RECOVER_INCOMPLETE}" -eq 0 ]]; then
  cid="$(compose ps -q mycenter 2>/dev/null || true)"
  [[ -n "${cid}" \
    && "$(docker inspect --format '{{.State.Running}}' "${cid}" 2>/dev/null || true)" == "true" ]] \
    || die "MyCenter must be running before a destructive restore"
  [[ "$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "${cid}" 2>/dev/null || true)" \
    == "unless-stopped" ]] || die "MyCenter restart policy must be unless-stopped before restore"
  wait_for_health || die "MyCenter must be healthy before a destructive restore"
fi

declare -A current_size=()
declare -A current_device=()
declare -A target_available=()
declare -A restored_size=()

load_target_metrics() {
  local metrics name bytes device available count=0
  metrics="$(volume_metrics)" || return 1
  current_size=()
  current_device=()
  target_available=()
  while read -r name bytes device available; do
    case "${name}" in data|files|web) ;; *) return 1 ;; esac
    [[ -z "${current_size[${name}]+present}" \
      && "${bytes}" =~ ^[0-9]+$ && "${device}" =~ ^[0-9]+$ \
      && "${available}" =~ ^[0-9]+$ ]] || return 1
    current_size["${name}"]="${bytes}"
    current_device["${name}"]="${device}"
    target_available["${name}"]="${available}"
    count=$((count + 1))
  done <<< "${metrics}"
  [[ "${count}" -eq 3 ]]
}

load_target_metrics || die "unable to read Docker volume capacity"
current_payload_bytes=0
restored_payload_bytes=0
for volume_name in data files web; do
  restored_size["${volume_name}"]="$(du -sb "${DRYRUN_DIR}/${volume_name}" | awk '{ print $1 }')"
  [[ "${restored_size[${volume_name}]}" =~ ^[0-9]+$ ]] \
    || die "unable to calculate restored volume size"
  current_payload_bytes=$((current_payload_bytes + current_size[${volume_name}]))
  restored_payload_bytes=$((restored_payload_bytes + restored_size[${volume_name}]))
done
trap restore_failure EXIT
if [[ "${RECOVER_INCOMPLETE}" -eq 0 ]]; then
  metadata_bytes="$(du -sb "${MYCENTER_DEPLOY_DIR}" "${MYCENTER_STATE_DIR}" \
    | awk '{ total += $1 } END { print total + 0 }')"
  backup_free_bytes="$(backup_available_bytes)"
  [[ "${metadata_bytes}" =~ ^[0-9]+$ && "${backup_free_bytes}" =~ ^[0-9]+$ ]] \
    || die "unable to calculate backup-volume capacity"
  (( backup_free_bytes > current_payload_bytes + metadata_bytes + 134217728 )) \
    || die "insufficient free space in meshcentral-backups for the pessimistic pre-restore backup bound"

  echo "Creating a pre-restore backup..."
  runtime_stopped_for_restore=1
  MYCENTER_OPERATION_LOCK_HELD=1 MYCENTER_BACKUP_LEAVE_STOPPED=1 \
    "${MYCENTER_TOOLS_LINK}/backup.sh"
else
  runtime_stopped_for_restore=1
  destructive_restore_started=1
  stop_runtime_proven || die "unable to prove MyCenter stopped before restore recovery"
fi

load_target_metrics || die "unable to calculate post-backup Docker volume capacity"
declare -A group_current=()
declare -A group_restored=()
declare -A group_available=()
for volume_name in data files web; do
  device="${current_device[${volume_name}]}"
  group_current["${device}"]=$(( ${group_current[${device}]:-0} + current_size[${volume_name}] ))
  group_restored["${device}"]=$(( ${group_restored[${device}]:-0} + restored_size[${volume_name}] ))
  if [[ -z "${group_available[${device}]+present}" \
    || "${target_available[${volume_name}]}" -lt "${group_available[${device}]}" ]]; then
    group_available["${device}"]="${target_available[${volume_name}]}"
  fi
done
for device in "${!group_current[@]}"; do
  (( group_available[${device}] + group_current[${device}] \
    > group_restored[${device}] + 134217728 )) \
    || die "a target Docker filesystem lacks replacement capacity"
done

if [[ "${RECOVER_INCOMPLETE}" -eq 0 ]]; then
  mark_maintenance_incomplete || die "unable to arm fail-closed restore protection"
fi
destructive_restore_started=1
docker run --rm \
  --network none \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,nodev,mode=1777,size=64m \
  --user 0:0 \
  --cap-drop ALL \
  --cap-add CHOWN \
  --cap-add DAC_OVERRIDE \
  --cap-add FOWNER \
  --security-opt no-new-privileges:true \
  --volume meshcentral-data:/target/data \
  --volume meshcentral-files:/target/files \
  --volume meshcentral-web:/target/web \
  --volume "${DRYRUN_DIR}:/restore:ro" \
  --entrypoint /bin/sh \
  "mycenter:${MYCENTER_IMAGE_TAG}" \
  -c '
    set -eu
    find /target/data -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
    find /target/files -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
    find /target/web -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
    cp -a /restore/data/. /target/data/
    cp -a /restore/files/. /target/files/
    cp -a /restore/web/. /target/web/
    chown -R 10001:10001 /target/data /target/files /target/web
  '

set_env_value MYCENTER_SESSION_KEY "${restored_session_key}"
export MYCENTER_SESSION_KEY="${restored_session_key}"
update_runtime_session_key
compose_unverified up -d --no-build --force-recreate mycenter
verify_runtime_restart_disabled
wait_for_health || die "data was restored, but MyCenter did not become healthy"
install_config_file "${MYCENTER_CONFIG_PATH}" "${current_release_dir}/config.json" root root
set_runtime_restart_policy
rm -f -- "${MAINTENANCE_MARKER}"
runtime_stopped_for_restore=0
destructive_restore_started=0
trap - EXIT INT TERM
cleanup_dryrun
echo "Restore applied successfully: ${ARCHIVE_REF}"
