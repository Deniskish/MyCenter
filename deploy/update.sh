#!/usr/bin/env bash
set -Eeuo pipefail

ENV_FILE="${MYCENTER_ENV_FILE:-/opt/mycenter/deploy/.env}"
LOCK_FILE="/run/lock/mycenter-operation.lock"
ACTION="${1:-update}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ "${EUID}" -eq 0 ]] || die "run this script as root"
[[ -f "${ENV_FILE}" ]] || die "missing ${ENV_FILE}"
[[ "$(stat -c '%a' "${ENV_FILE}")" == "600" ]] || die "${ENV_FILE} must have mode 600"
[[ "$(stat -c '%u' "${ENV_FILE}")" == "0" ]] || die "${ENV_FILE} must be owned by root"

exec 9>"${LOCK_FILE}"
flock -n 9 || die "another MyCenter maintenance operation is already running"

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

MYCENTER_SOURCE_DIR="${MYCENTER_SOURCE_DIR:-/opt/mycenter/src}"
MYCENTER_DEPLOY_DIR="${MYCENTER_DEPLOY_DIR:-/opt/mycenter/deploy}"
MYCENTER_STATE_DIR="${MYCENTER_STATE_DIR:-/opt/mycenter/state}"
MYCENTER_CONFIG_PATH="${MYCENTER_CONFIG_PATH:-${MYCENTER_DEPLOY_DIR}/config.json}"
MYCENTER_DEPLOYED_COMPOSE_PATH="${MYCENTER_DEPLOY_DIR}/docker-compose.yml"
CANDIDATE_COMPOSE_PATH="${MYCENTER_SOURCE_DIR}/deploy/docker-compose.yml"
MYCENTER_DEPLOYED_TEMPLATE_PATH="${MYCENTER_DEPLOY_DIR}/config.production.template.json"
CANDIDATE_TEMPLATE_PATH="${MYCENTER_SOURCE_DIR}/deploy/config.production.template.json"
RELEASES_DIR="${MYCENTER_STATE_DIR}/releases"
MYCENTER_TOOLS_LINK="${MYCENTER_DEPLOY_DIR}/current-tools"
MAINTENANCE_MARKER="${MYCENTER_STATE_DIR}/maintenance-incomplete"
BACKUP_RESTART_MARKER="/run/mycenter-backup-restart-needed"
export MYCENTER_SOURCE_DIR MYCENTER_DEPLOY_DIR MYCENTER_STATE_DIR MYCENTER_CONFIG_PATH
install -d -o root -g root -m 0750 "${MYCENTER_STATE_DIR}"

[[ "${MYCENTER_IMAGE_TAG:-}" =~ ^[0-9a-f]{7,40}$ ]] || die "current MYCENTER_IMAGE_TAG is invalid"
[[ "${MYCENTER_SESSION_KEY:-}" =~ ^[0-9a-f]{96}$ ]] || die "MYCENTER_SESSION_KEY is invalid"
[[ "${MYCENTER_REGISTRATION_TOKEN:-}" =~ ^[0-9a-f]{64}$ ]] \
  || die "the permanent registration guard is invalid"
[[ "${MYCENTER_BOOTSTRAP_ACTIVE:-true}" == "false" ]] \
  || die "the first-account bootstrap must be closed before update or rollback"
[[ "${MYCENTER_NEW_ACCOUNTS:-true}" == "false" ]] \
  || die "public registration must remain disabled during update or rollback"
[[ "${ACME_PRODUCTION:-false}" == "true" ]] \
  || die "production ACME must be active before update or rollback"
[[ -f "${MYCENTER_DEPLOYED_COMPOSE_PATH}" ]] || die "the deployed Compose definition is missing"
[[ -f "${MYCENTER_DEPLOYED_TEMPLATE_PATH}" ]] || die "the deployed config template is missing"

if [[ "${ACTION}" == "--recover-current" ]]; then
  [[ -f "${MAINTENANCE_MARKER}" ]] \
    || die "there is no incomplete maintenance state to recover"
else
  [[ ! -e "${MAINTENANCE_MARKER}" ]] \
    || die "incomplete destructive maintenance requires --recover-current"
fi
[[ ! -e "${BACKUP_RESTART_MARKER}" ]] \
  || die "an interrupted backup requires recovery before update or rollback"
if docker container inspect mycenter-backup-worker >/dev/null 2>&1; then
  die "a stale backup helper container requires recovery"
fi
[[ -s "${MYCENTER_STATE_DIR}/current-image-tag" ]] \
  || die "the current image-tag record is missing"
recorded_current_tag="$(tr -d '\r\n' < "${MYCENTER_STATE_DIR}/current-image-tag")"
if [[ "${ACTION}" != "--recover-current" ]]; then
  [[ "${recorded_current_tag}" == "${MYCENTER_IMAGE_TAG}" ]] \
    || die "the runtime image tag differs from the deployed tag record"
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

compose_with_file() {
  local compose_file="$1"
  shift
  MYCENTER_RESTART_POLICY=unless-stopped docker compose \
    --project-name mycenter \
    --env-file "${ENV_FILE}" \
    --file "${compose_file}" \
    "$@"
}

validate_candidate_source() {
  local agent_blob tool
  [[ -f "${CANDIDATE_COMPOSE_PATH}" ]] || die "the candidate Compose definition is missing"
  [[ -f "${CANDIDATE_TEMPLATE_PATH}" ]] || die "the candidate config template is missing"
  [[ -z "$(git -C "${MYCENTER_SOURCE_DIR}" status --porcelain)" ]] \
    || die "source checkout is not clean"
  for agent_blob in MeshCmd.exe MeshCmd64.exe MeshService.exe MeshService64.exe; do
    git -C "${MYCENTER_SOURCE_DIR}" cat-file -e "HEAD:agents/${agent_blob}" \
      || die "tracked Windows agent blob is missing from HEAD: ${agent_blob}"
  done
  for tool in deploy.sh backup.sh backup-recover.sh healthcheck.sh restore.sh update.sh; do
    [[ -f "${MYCENTER_SOURCE_DIR}/deploy/${tool}" ]] \
      || die "candidate maintenance tool is missing: ${tool}"
  done
}

install_compose_file() {
  local source_path="$1" destination_path="$2" tmp
  [[ -f "${source_path}" ]] || die "missing Compose definition: ${source_path}"
  tmp="$(mktemp "${destination_path}.tmp.XXXXXX")" || return 1
  if ! install -o root -g root -m 0640 "${source_path}" "${tmp}"; then
    rm -f -- "${tmp}"
    return 1
  fi
  mv -f -- "${tmp}" "${destination_path}" || {
    rm -f -- "${tmp}"
    return 1
  }
}

install_template_file() {
  local source_path="$1" destination_path="$2" tmp
  [[ -f "${source_path}" ]] || die "missing config template: ${source_path}"
  tmp="$(mktemp "${destination_path}.tmp.XXXXXX")" || return 1
  if ! install -o root -g root -m 0640 "${source_path}" "${tmp}"; then
    rm -f -- "${tmp}"
    return 1
  fi
  mv -f -- "${tmp}" "${destination_path}" || {
    rm -f -- "${tmp}"
    return 1
  }
}

release_compose_path() {
  local tag="$1"
  [[ "${tag}" =~ ^[0-9a-f]{7,40}$ ]] || die "invalid release tag"
  printf '%s/releases/%s/docker-compose.yml\n' "${MYCENTER_STATE_DIR}" "${tag}"
}

release_template_path() {
  local tag="$1"
  [[ "${tag}" =~ ^[0-9a-f]{7,40}$ ]] || die "invalid release tag"
  printf '%s/releases/%s/config.production.template.json\n' "${MYCENTER_STATE_DIR}" "${tag}"
}

release_config_path() {
  local tag="$1"
  [[ "${tag}" =~ ^[0-9a-f]{7,40}$ ]] || die "invalid release tag"
  printf '%s/releases/%s/config.json\n' "${MYCENTER_STATE_DIR}" "${tag}"
}

record_release_files() {
  local tag="$1" compose_source="$2" template_source="$3" config_source="$4" release_dir
  release_dir="${RELEASES_DIR}/${tag}"
  install -d -o root -g root -m 0750 "${release_dir}"
  install_compose_file "${compose_source}" "${release_dir}/docker-compose.yml"
  install_template_file "${template_source}" "${release_dir}/config.production.template.json"
  install_config_file "${config_source}" "${release_dir}/config.json" root root
}

release_tool_names=(deploy.sh backup.sh backup-recover.sh healthcheck.sh restore.sh update.sh)

record_release_tools() {
  local tag="$1" source_dir="$2" release_dir tools_dir tmp_dir tool
  [[ "${tag}" =~ ^[0-9a-f]{7,40}$ ]] || return 1
  release_dir="${RELEASES_DIR}/${tag}"
  tools_dir="${release_dir}/tools"
  install -d -o root -g root -m 0750 "${release_dir}" || return 1
  tmp_dir="$(mktemp -d "${release_dir}/tools.tmp.XXXXXX")" || return 1
  chmod 0750 "${tmp_dir}" || {
    rm -rf -- "${tmp_dir}"
    return 1
  }
  for tool in "${release_tool_names[@]}"; do
    if [[ ! -f "${source_dir}/${tool}" ]] \
      || ! install -o root -g root -m 0750 "${source_dir}/${tool}" "${tmp_dir}/${tool}"; then
      rm -rf -- "${tmp_dir}"
      return 1
    fi
  done
  if [[ -e "${tools_dir}" ]]; then
    for tool in "${release_tool_names[@]}"; do
      if ! cmp -s "${tmp_dir}/${tool}" "${tools_dir}/${tool}"; then
        rm -rf -- "${tmp_dir}"
        return 1
      fi
    done
    rm -rf -- "${tmp_dir}"
  else
    mv -- "${tmp_dir}" "${tools_dir}" || {
      rm -rf -- "${tmp_dir}"
      return 1
    }
  fi
}

release_tools_complete() {
  local tag="$1" tool tools_dir
  [[ "${tag}" =~ ^[0-9a-f]{7,40}$ ]] || return 1
  tools_dir="${RELEASES_DIR}/${tag}/tools"
  for tool in "${release_tool_names[@]}"; do
    [[ -x "${tools_dir}/${tool}" ]] || return 1
  done
}

activate_release_tools() {
  local tag="$1" tools_dir tmp_link
  release_tools_complete "${tag}" || return 1
  tools_dir="${RELEASES_DIR}/${tag}/tools"
  tmp_link="${MYCENTER_DEPLOY_DIR}/current-tools.tmp.$$"
  rm -f -- "${tmp_link}" || return 1
  ln -s "${tools_dir}" "${tmp_link}" || return 1
  mv -Tf -- "${tmp_link}" "${MYCENTER_TOOLS_LINK}" || {
    rm -f -- "${tmp_link}"
    return 1
  }
}

mark_maintenance_incomplete() {
  local operation="$1" tmp
  [[ "${operation}" =~ ^(update|rollback|recovery)$ ]] || return 1
  tmp="$(mktemp "${MYCENTER_STATE_DIR}/maintenance-incomplete.tmp.XXXXXX")" || return 1
  if ! printf '%s\n' "${operation}" > "${tmp}" || ! chown root:root "${tmp}" \
    || ! chmod 0600 "${tmp}"; then
    rm -f -- "${tmp}"
    return 1
  fi
  mv -f -- "${tmp}" "${MAINTENANCE_MARKER}" || {
    rm -f -- "${tmp}"
    return 1
  }
}

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

set_runtime_restart_policy() {
  local cid policy
  cid="$(compose ps -q mycenter 2>/dev/null || true)"
  [[ -n "${cid}" ]] || return 1
  docker update --restart=unless-stopped "${cid}" >/dev/null || return 1
  policy="$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "${cid}" 2>/dev/null || true)"
  [[ "${policy}" == "unless-stopped" ]]
}

verify_runtime_restart_disabled() {
  local cid policy
  cid="$(compose ps -q mycenter 2>/dev/null || true)"
  [[ -n "${cid}" ]] || return 1
  policy="$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "${cid}" 2>/dev/null || true)"
  [[ "${policy}" == "no" ]]
}

disable_runtime_restart_policy() {
  local cid policy running
  cid="$(compose ps -q mycenter 2>/dev/null || true)"
  [[ -n "${cid}" ]] || return 1
  running="$(docker inspect --format '{{.State.Running}}' "${cid}" 2>/dev/null || true)"
  policy="$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "${cid}" 2>/dev/null || true)"
  [[ "${running}" == "true" && "${policy}" == "unless-stopped" ]] || return 1
  wait_for_health || return 1
  docker update --restart=no "${cid}" >/dev/null || return 1
  policy="$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "${cid}" 2>/dev/null || true)"
  [[ "${policy}" == "no" ]]
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

record_tag() {
  local path="$1" value="$2" tmp
  tmp="$(mktemp "${MYCENTER_STATE_DIR}/tag.tmp.XXXXXX")" || return 1
  if ! printf '%s\n' "${value}" > "${tmp}"; then
    rm -f -- "${tmp}"
    return 1
  fi
  if ! chown root:root "${tmp}" || ! chmod 0600 "${tmp}"; then
    rm -f -- "${tmp}"
    return 1
  fi
  mv -f -- "${tmp}" "${path}" || {
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

install_reconciled_config() {
  local source_path="$1" tmp
  [[ -f "${source_path}" ]] || return 1
  tmp="$(mktemp "${MYCENTER_CONFIG_PATH}.tmp.XXXXXX")" || return 1
  if ! jq \
    --arg domain "${MYCENTER_DOMAIN}" \
    --arg email "${ACME_EMAIL}" \
    --argjson production "${ACME_PRODUCTION}" \
    '.settings.cert = $domain
      | .settings.sessionKey = env.MYCENTER_SESSION_KEY
      | .domains[""].newAccounts = false
      | .domains[""].newAccountsPass = env.MYCENTER_REGISTRATION_TOKEN
      | .letsEncrypt.email = $email
      | .letsEncrypt.names = $domain
      | .letsEncrypt.production = $production' \
    "${source_path}" > "${tmp}" \
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

RECOVERY_TAG=""
RECOVERY_CONFIG=""
RECOVERY_COMPOSE=""
RECOVERY_TEMPLATE=""
RECOVERY_CURRENT_TAG_EXISTS=0
RECOVERY_CURRENT_TAG_VALUE=""
RECOVERY_PREVIOUS_TAG_EXISTS=0
RECOVERY_PREVIOUS_TAG_VALUE=""

recover_runtime_on_failure() {
  local exit_code="${1:-1}" config_status=0 env_status=0 definition_status=0
  local template_status=0 compose_status=0 restart_guard_status=0 health_status=0 metadata_status=0
  local tools_status=0 marker_status=0 stop_status=0
  [[ "${exit_code}" -ne 0 ]] || exit_code=1
  trap - ERR INT TERM EXIT
  set +e
  echo "Maintenance action failed; restoring the previous runtime..." >&2
  if [[ -n "${RECOVERY_CONFIG}" ]]; then
    if [[ -f "${RECOVERY_CONFIG}" ]]; then
      install_config_file "${RECOVERY_CONFIG}"
      config_status=$?
    else
      config_status=1
    fi
  fi
  if [[ -n "${RECOVERY_COMPOSE}" ]]; then
    if [[ -f "${RECOVERY_COMPOSE}" ]]; then
      install_compose_file "${RECOVERY_COMPOSE}" "${MYCENTER_DEPLOYED_COMPOSE_PATH}"
      definition_status=$?
    else
      definition_status=1
    fi
  fi
  if [[ -n "${RECOVERY_TEMPLATE}" ]]; then
    if [[ -f "${RECOVERY_TEMPLATE}" ]]; then
      install_template_file "${RECOVERY_TEMPLATE}" "${MYCENTER_DEPLOYED_TEMPLATE_PATH}"
      template_status=$?
    else
      template_status=1
    fi
  fi
  set_env_value MYCENTER_IMAGE_TAG "${RECOVERY_TAG}"
  env_status=$?
  export MYCENTER_IMAGE_TAG="${RECOVERY_TAG}"
  compose_unverified up -d --no-build --force-recreate mycenter
  compose_status=$?
  if [[ "${compose_status}" -eq 0 ]]; then
    verify_runtime_restart_disabled
    restart_guard_status=$?
    if [[ "${restart_guard_status}" -eq 0 ]]; then
      wait_for_health
      health_status=$?
    else
      health_status=1
    fi
  else
    health_status=1
  fi
  if [[ "${RECOVERY_CURRENT_TAG_EXISTS}" -eq 1 ]]; then
    record_tag "${MYCENTER_STATE_DIR}/current-image-tag" "${RECOVERY_CURRENT_TAG_VALUE}" \
      || metadata_status=1
  else
    rm -f -- "${MYCENTER_STATE_DIR}/current-image-tag" || metadata_status=1
  fi
  if [[ "${RECOVERY_PREVIOUS_TAG_EXISTS}" -eq 1 ]]; then
    record_tag "${MYCENTER_STATE_DIR}/previous-image-tag" "${RECOVERY_PREVIOUS_TAG_VALUE}" \
      || metadata_status=1
  else
    rm -f -- "${MYCENTER_STATE_DIR}/previous-image-tag" || metadata_status=1
  fi
  activate_release_tools "${RECOVERY_TAG}" || tools_status=1
  if [[ "${config_status}" -eq 0 && "${definition_status}" -eq 0 \
    && "${template_status}" -eq 0 && "${env_status}" -eq 0 \
    && "${compose_status}" -eq 0 && "${restart_guard_status}" -eq 0 \
    && "${health_status}" -eq 0 \
    && "${metadata_status}" -eq 0 && "${tools_status}" -eq 0 ]]; then
    set_runtime_restart_policy || tools_status=1
  fi
  if [[ "${config_status}" -eq 0 && "${definition_status}" -eq 0 \
    && "${template_status}" -eq 0 && "${env_status}" -eq 0 \
    && "${compose_status}" -eq 0 && "${restart_guard_status}" -eq 0 \
    && "${health_status}" -eq 0 \
    && "${metadata_status}" -eq 0 && "${tools_status}" -eq 0 ]]; then
    rm -f -- "${MAINTENANCE_MARKER}" || marker_status=1
  else
    marker_status=1
  fi
  if [[ "${marker_status}" -eq 0 ]]; then
    [[ -z "${RECOVERY_CONFIG}" ]] || rm -f -- "${RECOVERY_CONFIG}"
    [[ -z "${RECOVERY_COMPOSE}" ]] || rm -f -- "${RECOVERY_COMPOSE}"
    [[ -z "${RECOVERY_TEMPLATE}" ]] || rm -f -- "${RECOVERY_TEMPLATE}"
    echo "Previous runtime restored: mycenter:${RECOVERY_TAG}" >&2
  else
    stop_runtime_proven || stop_status=1
    mark_maintenance_incomplete recovery >/dev/null 2>&1 || true
    echo "Automatic runtime recovery failed; manual diagnosis is required." >&2
    if [[ "${stop_status}" -eq 0 ]]; then
      echo "MyCenter was stopped and the persistent maintenance marker was retained." >&2
    else
      echo "CRITICAL: MyCenter could not be proven stopped; inspect the exact container immediately." >&2
    fi
    echo "Root-only recovery snapshots were retained in ${MYCENTER_STATE_DIR}." >&2
  fi
  exit "${exit_code}"
}

arm_runtime_recovery() {
  RECOVERY_TAG="$1"
  RECOVERY_CONFIG="${2:-}"
  RECOVERY_COMPOSE="${3:-}"
  RECOVERY_TEMPLATE="${4:-}"
  if [[ -s "${MYCENTER_STATE_DIR}/current-image-tag" ]]; then
    RECOVERY_CURRENT_TAG_EXISTS=1
    RECOVERY_CURRENT_TAG_VALUE="$(tr -d '\r\n' < "${MYCENTER_STATE_DIR}/current-image-tag")"
    [[ "${RECOVERY_CURRENT_TAG_VALUE}" =~ ^[0-9a-f]{7,40}$ ]] \
      || die "current image-tag record is invalid"
  fi
  if [[ -s "${MYCENTER_STATE_DIR}/previous-image-tag" ]]; then
    RECOVERY_PREVIOUS_TAG_EXISTS=1
    RECOVERY_PREVIOUS_TAG_VALUE="$(tr -d '\r\n' < "${MYCENTER_STATE_DIR}/previous-image-tag")"
    [[ "${RECOVERY_PREVIOUS_TAG_VALUE}" =~ ^[0-9a-f]{7,40}$ ]] \
      || die "previous image-tag record is invalid"
  fi
  trap 'recover_runtime_on_failure "$?"' ERR INT TERM EXIT
}

disarm_runtime_recovery() {
  trap - ERR INT TERM EXIT
  RECOVERY_TAG=""
  RECOVERY_CONFIG=""
  RECOVERY_COMPOSE=""
  RECOVERY_TEMPLATE=""
  RECOVERY_CURRENT_TAG_EXISTS=0
  RECOVERY_CURRENT_TAG_VALUE=""
  RECOVERY_PREVIOUS_TAG_EXISTS=0
  RECOVERY_PREVIOUS_TAG_VALUE=""
}

rollback_to_tag() {
  local target_tag="$1" current_tag="$2" target_compose target_template target_config
  local current_config current_compose current_template cleanup_status=0
  [[ "${target_tag}" =~ ^[0-9a-f]{7,40}$ ]] || die "stored rollback tag is invalid"
  docker image inspect "mycenter:${target_tag}" >/dev/null 2>&1 \
    || die "rollback image mycenter:${target_tag} is not present"
  target_compose="$(release_compose_path "${target_tag}")"
  target_template="$(release_template_path "${target_tag}")"
  target_config="$(release_config_path "${target_tag}")"
  [[ -s "${target_compose}" && -s "${target_template}" && -s "${target_config}" ]] \
    || die "the rollback release snapshot is incomplete"
  release_tools_complete "${target_tag}" \
    || die "the rollback maintenance tools are incomplete"

  current_config="$(mktemp "${MYCENTER_STATE_DIR}/config.before-rollback.XXXXXX")"
  install -o root -g root -m 0600 "${MYCENTER_CONFIG_PATH}" "${current_config}"
  current_compose="$(mktemp "${MYCENTER_STATE_DIR}/compose.before-rollback.XXXXXX")"
  install -o root -g root -m 0640 "${MYCENTER_DEPLOYED_COMPOSE_PATH}" "${current_compose}"
  current_template="$(mktemp "${MYCENTER_STATE_DIR}/template.before-rollback.XXXXXX")"
  install -o root -g root -m 0640 "${MYCENTER_DEPLOYED_TEMPLATE_PATH}" "${current_template}"
  arm_runtime_recovery "${current_tag}" "${current_config}" "${current_compose}" "${current_template}"
  MYCENTER_OPERATION_LOCK_HELD=1 MYCENTER_BACKUP_LEAVE_STOPPED=1 \
    "${MYCENTER_TOOLS_LINK}/backup.sh"
  mark_maintenance_incomplete rollback
  install_compose_file "${target_compose}" "${MYCENTER_DEPLOYED_COMPOSE_PATH}"
  install_template_file "${target_template}" "${MYCENTER_DEPLOYED_TEMPLATE_PATH}"
  set_env_value MYCENTER_IMAGE_TAG "${target_tag}"
  export MYCENTER_IMAGE_TAG="${target_tag}"
  install_reconciled_config "${target_config}"
  compose config --quiet
  compose_unverified up -d --no-build --force-recreate mycenter
  verify_runtime_restart_disabled
  wait_for_health
  record_release_files "${target_tag}" \
    "${MYCENTER_DEPLOYED_COMPOSE_PATH}" \
    "${MYCENTER_DEPLOYED_TEMPLATE_PATH}" \
    "${MYCENTER_CONFIG_PATH}"
  record_tag "${MYCENTER_STATE_DIR}/previous-image-tag" "${current_tag}"
  record_tag "${MYCENTER_STATE_DIR}/current-image-tag" "${target_tag}"
  activate_release_tools "${target_tag}"
  set_runtime_restart_policy
  rm -f -- "${MAINTENANCE_MARKER}"
  rm -f -- "${current_config}" "${current_compose}" "${current_template}" \
    || cleanup_status=1
  disarm_runtime_recovery
  [[ "${cleanup_status}" -eq 0 ]] \
    || echo "WARNING: a root-only rollback snapshot requires manual cleanup in ${MYCENTER_STATE_DIR}." >&2
  echo "Rollback completed: mycenter:${target_tag}"
}

recover_current_failed() {
  local exit_code=$? stop_status=0
  [[ "${exit_code}" -ne 0 ]] || exit_code=1
  trap - ERR INT TERM EXIT
  set +e
  stop_runtime_proven || stop_status=1
  echo "Recovery to the recorded current release failed; the maintenance marker was retained." >&2
  if [[ "${stop_status}" -eq 0 ]]; then
    echo "MyCenter is stopped for diagnosis." >&2
  else
    echo "CRITICAL: MyCenter could not be proven stopped; inspect the exact container immediately." >&2
  fi
  exit "${exit_code}"
}

recover_current_release() {
  local confirmation="$1" marker_operation tag release_dir
  [[ "${confirmation}" == "RECOVER_CURRENT" ]] \
    || die "recovery requires: --recover-current RECOVER_CURRENT"
  marker_operation="$(tr -d '\r\n' < "${MAINTENANCE_MARKER}")"
  case "${marker_operation}" in
    update|rollback|recovery) ;;
    restore)
      die "an interrupted data restore requires restore.sh --recover-incomplete"
      ;;
    *)
      die "the maintenance marker contains an unknown operation"
      ;;
  esac

  tag="${recorded_current_tag}"
  release_dir="${RELEASES_DIR}/${tag}"
  [[ "${tag}" =~ ^[0-9a-f]{7,40}$ \
    && -s "${release_dir}/docker-compose.yml" \
    && -s "${release_dir}/config.production.template.json" \
    && -s "${release_dir}/config.json" ]] \
    || die "the recorded current release snapshot is incomplete"
  release_tools_complete "${tag}" \
    || die "the recorded current release tools are incomplete"
  docker image inspect "mycenter:${tag}" >/dev/null 2>&1 \
    || die "the recorded current image is missing"
  jq --exit-status \
    '.settings.cert == env.MYCENTER_DOMAIN
      and .settings.sessionKey == env.MYCENTER_SESSION_KEY
      and .domains[""].newAccounts == false
      and .domains[""].newAccountsPass == env.MYCENTER_REGISTRATION_TOKEN
      and .letsEncrypt.production == true' \
    "${release_dir}/config.json" >/dev/null \
    || die "the recorded current config does not match protected runtime policy"

  trap recover_current_failed ERR INT TERM EXIT
  stop_runtime_proven
  install_compose_file "${release_dir}/docker-compose.yml" "${MYCENTER_DEPLOYED_COMPOSE_PATH}"
  install_template_file "${release_dir}/config.production.template.json" "${MYCENTER_DEPLOYED_TEMPLATE_PATH}"
  install_config_file "${release_dir}/config.json"
  set_env_value MYCENTER_IMAGE_TAG "${tag}"
  export MYCENTER_IMAGE_TAG="${tag}"
  compose config --quiet
  compose_unverified up -d --no-build --force-recreate mycenter
  verify_runtime_restart_disabled
  wait_for_health
  activate_release_tools "${tag}"
  set_runtime_restart_policy
  rm -f -- "${MAINTENANCE_MARKER}"
  trap - ERR INT TERM EXIT
  echo "Recovered recorded current release: mycenter:${tag}"
}

case "${ACTION}" in
  --recover-current)
    recover_current_release "${2:-}"
    exit 0
    ;;
  --rollback)
    [[ -s "${MYCENTER_STATE_DIR}/previous-image-tag" ]] || die "no previous image tag is recorded"
    previous_tag="$(tr -d '\r\n' < "${MYCENTER_STATE_DIR}/previous-image-tag")"
    rollback_to_tag "${previous_tag}" "${MYCENTER_IMAGE_TAG}"
    exit 0
    ;;
  update)
    [[ ! -e /var/run/reboot-required ]] || die "the VPS requires a reboot before update"
    validate_candidate_source
    ;;
  *)
    die "usage: $0 [update|--rollback|--recover-current RECOVER_CURRENT]"
    ;;
esac

old_tag="${MYCENTER_IMAGE_TAG}"
new_tag="$(git -C "${MYCENTER_SOURCE_DIR}" rev-parse --short=12 HEAD)"
[[ "${new_tag}" =~ ^[0-9a-f]{12}$ ]] || die "unable to derive new image tag"
[[ "${new_tag}" != "${old_tag}" ]] || die "current checkout is already deployed as ${old_tag}"
old_release_compose="$(release_compose_path "${old_tag}")"
old_release_template="$(release_template_path "${old_tag}")"
old_release_config="$(release_config_path "${old_tag}")"
[[ -s "${old_release_compose}" && -s "${old_release_template}" \
  && -s "${old_release_config}" ]] || die "the current release snapshot is incomplete"
release_tools_complete "${old_tag}" || die "the current release maintenance tools are incomplete"
[[ "$(readlink -f "${MYCENTER_TOOLS_LINK}" 2>/dev/null || true)" \
  == "$(readlink -f "${RELEASES_DIR}/${old_tag}/tools")" ]] \
  || die "the active maintenance tools do not match the current release"
cmp -s "${old_release_compose}" "${MYCENTER_DEPLOYED_COMPOSE_PATH}" \
  || die "the deployed Compose definition differs from the current release snapshot"
cmp -s "${old_release_template}" "${MYCENTER_DEPLOYED_TEMPLATE_PATH}" \
  || die "the deployed config template differs from the current release snapshot"
cmp -s "${old_release_config}" "${MYCENTER_CONFIG_PATH}" \
  || die "the runtime config differs from the current release snapshot"

echo "Creating a pre-update backup..."
MYCENTER_OPERATION_LOCK_HELD=1 "${MYCENTER_TOOLS_LINK}/backup.sh"

export MYCENTER_IMAGE_TAG="${new_tag}"
compose_with_file "${CANDIDATE_COMPOSE_PATH}" build --pull mycenter
docker image inspect "mycenter:${new_tag}" >/dev/null

config_before="$(mktemp "${MYCENTER_STATE_DIR}/config.before-update.XXXXXX")"
install -o root -g root -m 0600 "${MYCENTER_CONFIG_PATH}" "${config_before}"
compose_before="$(mktemp "${MYCENTER_STATE_DIR}/compose.before-update.XXXXXX")"
install -o root -g root -m 0640 "${MYCENTER_DEPLOYED_COMPOSE_PATH}" "${compose_before}"
template_before="$(mktemp "${MYCENTER_STATE_DIR}/template.before-update.XXXXXX")"
install -o root -g root -m 0640 "${MYCENTER_DEPLOYED_TEMPLATE_PATH}" "${template_before}"
arm_runtime_recovery "${old_tag}" "${config_before}" "${compose_before}" "${template_before}"
disable_runtime_restart_policy
mark_maintenance_incomplete update

set_env_value MYCENTER_IMAGE_TAG "${new_tag}"
compose_with_file "${CANDIDATE_COMPOSE_PATH}" config --quiet
install_compose_file "${CANDIDATE_COMPOSE_PATH}" "${MYCENTER_DEPLOYED_COMPOSE_PATH}"
install_template_file "${CANDIDATE_TEMPLATE_PATH}" "${MYCENTER_DEPLOYED_TEMPLATE_PATH}"
MYCENTER_OPERATION_LOCK_HELD=1 MYCENTER_ALLOW_PENDING_IMAGE_TAG=1 \
  "${MYCENTER_SOURCE_DIR}/deploy/deploy.sh" --render-only
compose_unverified up -d --no-build --force-recreate mycenter
verify_runtime_restart_disabled
wait_for_health
record_release_files "${new_tag}" \
  "${MYCENTER_DEPLOYED_COMPOSE_PATH}" \
  "${MYCENTER_DEPLOYED_TEMPLATE_PATH}" \
  "${MYCENTER_CONFIG_PATH}"
record_release_tools "${new_tag}" "${MYCENTER_SOURCE_DIR}/deploy"
record_tag "${MYCENTER_STATE_DIR}/previous-image-tag" "${old_tag}"
record_tag "${MYCENTER_STATE_DIR}/current-image-tag" "${new_tag}"
activate_release_tools "${new_tag}"
set_runtime_restart_policy
rm -f -- "${MAINTENANCE_MARKER}"
cleanup_status=0
rm -f -- "${config_before}" "${compose_before}" "${template_before}" \
  || cleanup_status=1
disarm_runtime_recovery
[[ "${cleanup_status}" -eq 0 ]] \
  || echo "WARNING: a root-only update snapshot requires manual cleanup in ${MYCENTER_STATE_DIR}." >&2
echo "Update completed: mycenter:${new_tag}"
echo "Previous image retained: mycenter:${old_tag}"
