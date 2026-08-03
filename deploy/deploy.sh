#!/usr/bin/env bash
set -Eeuo pipefail

ENV_FILE="${MYCENTER_ENV_FILE:-/opt/mycenter/deploy/.env}"
ACTION="${1:-deploy}"
CLOSE_CONFIRMATION="${2:-}"
OPERATION_LOCK_FILE="/run/lock/mycenter-operation.lock"
OPERATION_LOCK_OWNED=0
COMPOSE_FILE_OVERRIDE=""

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "run this script as root"
}

validate_env_file() {
  [[ -f "${ENV_FILE}" ]] || die "missing ${ENV_FILE}; create it from deploy/.env.example"
  [[ "$(stat -c '%a' "${ENV_FILE}")" == "600" ]] || die "${ENV_FILE} must have mode 600"
  [[ "$(stat -c '%u' "${ENV_FILE}")" == "0" ]] || die "${ENV_FILE} must be owned by root"
}

load_env() {
  validate_env_file
  set -a
  # The file is root-owned and mode 600 before it is sourced.
  # shellcheck disable=SC1090
  source "${ENV_FILE}" || return 1
  set +a

  MYCENTER_SOURCE_DIR="${MYCENTER_SOURCE_DIR:-/opt/mycenter/src}"
  MYCENTER_DEPLOY_DIR="${MYCENTER_DEPLOY_DIR:-/opt/mycenter/deploy}"
  MYCENTER_STATE_DIR="${MYCENTER_STATE_DIR:-/opt/mycenter/state}"
  MYCENTER_CONFIG_PATH="${MYCENTER_CONFIG_PATH:-${MYCENTER_DEPLOY_DIR}/config.json}"
  MYCENTER_DEPLOYED_COMPOSE_PATH="${MYCENTER_DEPLOY_DIR}/docker-compose.yml"
  MYCENTER_DEPLOYED_TEMPLATE_PATH="${MYCENTER_DEPLOY_DIR}/config.production.template.json"
  MYCENTER_TOOLS_LINK="${MYCENTER_DEPLOY_DIR}/current-tools"
  MYCENTER_MAINTENANCE_MARKER="${MYCENTER_STATE_DIR}/maintenance-incomplete"
  ACME_PRODUCTION="${ACME_PRODUCTION:-false}"
  MYCENTER_NEW_ACCOUNTS="${MYCENTER_NEW_ACCOUNTS:-false}"
  MYCENTER_ENABLE_IPV6="${MYCENTER_ENABLE_IPV6:-false}"
  MYCENTER_REGISTRATION_TOKEN="${MYCENTER_REGISTRATION_TOKEN:-}"
  MYCENTER_BOOTSTRAP_ACTIVE="${MYCENTER_BOOTSTRAP_ACTIVE:-true}"

  export MYCENTER_SOURCE_DIR MYCENTER_DEPLOY_DIR MYCENTER_STATE_DIR
  export MYCENTER_CONFIG_PATH ACME_PRODUCTION MYCENTER_NEW_ACCOUNTS
  export MYCENTER_ENABLE_IPV6 MYCENTER_IMAGE_TAG MYCENTER_DOMAIN
  export MYCENTER_SESSION_KEY
  export MYCENTER_REGISTRATION_TOKEN MYCENTER_BOOTSTRAP_ACTIVE
  export MYCENTER_DEPLOYED_COMPOSE_PATH
  export MYCENTER_DEPLOYED_TEMPLATE_PATH
  export MYCENTER_TOOLS_LINK MYCENTER_MAINTENANCE_MARKER
}

validate_values() {
  [[ "${MYCENTER_DOMAIN:-}" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ ]] || die "invalid MYCENTER_DOMAIN"
  [[ "${MYCENTER_DOMAIN}" == *.* && "${MYCENTER_DOMAIN}" != *..* ]] || die "MYCENTER_DOMAIN must be an FQDN"
  [[ "${ACME_EMAIL:-}" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] || die "invalid ACME_EMAIL"
  [[ "${MYCENTER_PUBLIC_IPV4:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid MYCENTER_PUBLIC_IPV4"
  [[ "${ACME_PRODUCTION}" =~ ^(true|false)$ ]] || die "ACME_PRODUCTION must be true or false"
  [[ "${MYCENTER_NEW_ACCOUNTS}" =~ ^(true|false)$ ]] || die "MYCENTER_NEW_ACCOUNTS must be true or false"
  [[ "${MYCENTER_ENABLE_IPV6}" =~ ^(true|false)$ ]] || die "MYCENTER_ENABLE_IPV6 must be true or false"
  [[ "${MYCENTER_BOOTSTRAP_ACTIVE}" =~ ^(true|false)$ ]] \
    || die "MYCENTER_BOOTSTRAP_ACTIVE must be true or false"
  [[ "${MYCENTER_REGISTRATION_TOKEN}" == "GENERATE_ON_VPS" \
    || "${MYCENTER_REGISTRATION_TOKEN}" =~ ^[0-9a-f]{64}$ ]] \
    || die "MYCENTER_REGISTRATION_TOKEN has an invalid shape"
  [[ -d "${MYCENTER_SOURCE_DIR}/.git" ]] || die "${MYCENTER_SOURCE_DIR} is not a Git checkout"
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

compose() {
  local compose_file
  compose_file="${COMPOSE_FILE_OVERRIDE:-${MYCENTER_DEPLOYED_COMPOSE_PATH}}"
  if [[ ! -f "${compose_file}" ]]; then
    compose_file="${MYCENTER_SOURCE_DIR}/deploy/docker-compose.yml"
  fi
  MYCENTER_RESTART_POLICY=unless-stopped docker compose \
    --project-name mycenter \
    --env-file "${ENV_FILE}" \
    --file "${compose_file}" \
    "$@"
}

install_deployed_compose() {
  local source_path="$1" tmp
  [[ -f "${source_path}" ]] || die "missing Compose definition: ${source_path}"
  install -d -o root -g root -m 0750 "${MYCENTER_DEPLOY_DIR}"
  tmp="$(mktemp "${MYCENTER_DEPLOYED_COMPOSE_PATH}.tmp.XXXXXX")" || return 1
  if ! install -o root -g root -m 0640 "${source_path}" "${tmp}"; then
    rm -f -- "${tmp}"
    return 1
  fi
  mv -f -- "${tmp}" "${MYCENTER_DEPLOYED_COMPOSE_PATH}" || {
    rm -f -- "${tmp}"
    return 1
  }
}

install_deployed_template() {
  local source_path="$1" tmp
  [[ -f "${source_path}" ]] || die "missing config template: ${source_path}"
  install -d -o root -g root -m 0750 "${MYCENTER_DEPLOY_DIR}"
  tmp="$(mktemp "${MYCENTER_DEPLOYED_TEMPLATE_PATH}.tmp.XXXXXX")" || return 1
  if ! install -o root -g root -m 0640 "${source_path}" "${tmp}"; then
    rm -f -- "${tmp}"
    return 1
  fi
  mv -f -- "${tmp}" "${MYCENTER_DEPLOYED_TEMPLATE_PATH}" || {
    rm -f -- "${tmp}"
    return 1
  }
}

record_release_file() {
  local source_path="$1" destination_path="$2" mode="$3" tmp
  tmp="$(mktemp "${destination_path}.tmp.XXXXXX")" || return 1
  if ! install -o root -g root -m "${mode}" "${source_path}" "${tmp}"; then
    rm -f -- "${tmp}"
    return 1
  fi
  mv -f -- "${tmp}" "${destination_path}" || {
    rm -f -- "${tmp}"
    return 1
  }
}

record_release_files() {
  local tag="$1" release_dir
  [[ "${tag}" =~ ^[0-9a-f]{7,40}$ ]] || die "invalid release tag"
  release_dir="${MYCENTER_STATE_DIR}/releases/${tag}"
  install -d -o root -g root -m 0750 "${release_dir}"
  record_release_file \
    "${MYCENTER_DEPLOYED_COMPOSE_PATH}" "${release_dir}/docker-compose.yml" 0640
  record_release_file \
    "${MYCENTER_DEPLOYED_TEMPLATE_PATH}" "${release_dir}/config.production.template.json" 0640
  record_release_file \
    "${MYCENTER_CONFIG_PATH}" "${release_dir}/config.json" 0600
}

release_tool_names=(deploy.sh backup.sh backup-recover.sh healthcheck.sh restore.sh update.sh)

record_release_tools() {
  local tag="$1" source_dir="$2" release_dir tools_dir tmp_dir tool
  [[ "${tag}" =~ ^[0-9a-f]{7,40}$ ]] || die "invalid release tag"
  release_dir="${MYCENTER_STATE_DIR}/releases/${tag}"
  tools_dir="${release_dir}/tools"
  install -d -o root -g root -m 0750 "${release_dir}"
  tmp_dir="$(mktemp -d "${release_dir}/tools.tmp.XXXXXX")" || return 1
  chmod 0750 "${tmp_dir}"
  for tool in "${release_tool_names[@]}"; do
    if [[ ! -f "${source_dir}/${tool}" ]] \
      || ! install -o root -g root -m 0750 "${source_dir}/${tool}" "${tmp_dir}/${tool}"; then
      rm -rf -- "${tmp_dir}"
      return 1
    fi
  done
  if [[ -e "${tools_dir}" ]]; then
    for tool in "${release_tool_names[@]}"; do
      cmp -s "${tmp_dir}/${tool}" "${tools_dir}/${tool}" || {
        rm -rf -- "${tmp_dir}"
        die "release tools already exist with different content: ${tag}"
      }
    done
    rm -rf -- "${tmp_dir}"
  else
    mv -- "${tmp_dir}" "${tools_dir}" || {
      rm -rf -- "${tmp_dir}"
      return 1
    }
  fi
}

activate_release_tools() {
  local tag="$1" tools_dir tmp_link
  [[ "${tag}" =~ ^[0-9a-f]{7,40}$ ]] || die "invalid release tag"
  tools_dir="${MYCENTER_STATE_DIR}/releases/${tag}/tools"
  for tool in "${release_tool_names[@]}"; do
    [[ -x "${tools_dir}/${tool}" ]] || die "release maintenance tool is missing: ${tool}"
  done
  tmp_link="${MYCENTER_DEPLOY_DIR}/current-tools.tmp.$$"
  rm -f -- "${tmp_link}"
  ln -s "${tools_dir}" "${tmp_link}"
  mv -Tf -- "${tmp_link}" "${MYCENTER_TOOLS_LINK}"
}

record_current_image_tag() {
  local tmp
  tmp="$(mktemp "${MYCENTER_STATE_DIR}/current-image-tag.tmp.XXXXXX")" || return 1
  if ! printf '%s\n' "${MYCENTER_IMAGE_TAG}" > "${tmp}" \
    || ! chown root:root "${tmp}" || ! chmod 0600 "${tmp}"; then
    rm -f -- "${tmp}"
    return 1
  fi
  mv -f -- "${tmp}" "${MYCENTER_STATE_DIR}/current-image-tag" || {
    rm -f -- "${tmp}"
    return 1
  }
}

wait_for_health() {
  local attempts="${1:-120}" cid state health
  for ((i = 1; i <= attempts; i++)); do
    cid="$(compose ps -q mycenter 2>/dev/null || true)"
    if [[ -n "${cid}" ]]; then
      state="$(docker inspect --format '{{.State.Status}}' "${cid}" 2>/dev/null || true)"
      health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${cid}" 2>/dev/null || true)"
      if [[ "${state}" == "running" && "${health}" == "healthy" ]]; then
        return 0
      fi
      if [[ "${state}" == "exited" || "${state}" == "dead" ]]; then
        echo "Container state: ${state}" >&2
        return 1
      fi
    fi
    sleep 5
  done
  echo "Container did not become healthy in time" >&2
  return 1
}

verify_runtime_restart_policy() {
  local cid policy
  cid="$(compose ps -q mycenter 2>/dev/null || true)"
  [[ -n "${cid}" ]] || return 1
  policy="$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "${cid}" 2>/dev/null || true)"
  [[ "${policy}" == "unless-stopped" ]]
}

wait_for_acme_files() {
  local mode="$1" attempts="${2:-120}"
  [[ "${mode}" == "staging" || "${mode}" == "production" ]] \
    || die "invalid ACME certificate mode"
  for ((i = 1; i <= attempts; i++)); do
    if compose exec -T mycenter \
      test -s "/opt/meshcentral/meshcentral-data/letsencrypt-certs/${mode}.crt" \
      && compose exec -T mycenter \
        test -s "/opt/meshcentral/meshcentral-data/letsencrypt-certs/${mode}.key"; then
      return 0
    fi
    sleep 5
  done
  return 1
}

check_dns() {
  command -v dig >/dev/null 2>&1 || die "dig is required (install dnsutils)"
  local a_records aaaa_records
  a_records="$(dig +short A "${MYCENTER_DOMAIN}" \
    | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' \
    | sort -u || true)"
  [[ "${a_records}" == "${MYCENTER_PUBLIC_IPV4}" ]] || {
    echo "Resolved A records:" >&2
    sed 's/^/  /' <<<"${a_records:-<none>}" >&2
    die "${MYCENTER_DOMAIN} must resolve only to MYCENTER_PUBLIC_IPV4"
  }

  aaaa_records="$(dig +short AAAA "${MYCENTER_DOMAIN}" \
    | grep -E '^[0-9A-Fa-f:]+$' \
    | sort -u || true)"
  if [[ "${MYCENTER_ENABLE_IPV6}" == "false" && -n "${aaaa_records}" ]]; then
    echo "Resolved AAAA records:" >&2
    sed 's/^/  /' <<<"${aaaa_records}" >&2
    die "AAAA exists while MYCENTER_ENABLE_IPV6=false"
  fi
}

prepare_initial_runtime_values() {
  local short_commit
  short_commit="$(git -C "${MYCENTER_SOURCE_DIR}" rev-parse --short=12 HEAD)"
  [[ "${short_commit}" =~ ^[0-9a-f]{12}$ ]] || die "unable to derive a versioned image tag"
  if [[ "${MYCENTER_IMAGE_TAG:-}" != "${short_commit}" ]]; then
    set_env_value MYCENTER_IMAGE_TAG "${short_commit}"
  fi

  if [[ -z "${MYCENTER_SESSION_KEY:-}" || "${MYCENTER_SESSION_KEY}" == "GENERATE_ON_VPS" ]]; then
    set_env_value MYCENTER_SESSION_KEY "$(openssl rand -hex 48)"
  fi
  if [[ -z "${MYCENTER_REGISTRATION_TOKEN:-}" \
    || "${MYCENTER_REGISTRATION_TOKEN}" == "GENERATE_ON_VPS" ]]; then
    set_env_value MYCENTER_REGISTRATION_TOKEN "$(openssl rand -hex 32)"
  fi
  load_env
  [[ "${MYCENTER_SESSION_KEY}" =~ ^[0-9a-f]{96}$ ]] || die "MYCENTER_SESSION_KEY must be a 96-character generated hex value"
  [[ "${MYCENTER_REGISTRATION_TOKEN}" =~ ^[0-9a-f]{64}$ ]] \
    || die "MYCENTER_REGISTRATION_TOKEN must be a generated 64-character hex value"
}

require_deployed_runtime_values() {
  local recorded_tag
  [[ -f "${MYCENTER_DEPLOYED_COMPOSE_PATH}" ]] \
    || die "the deployed Compose definition is missing"
  [[ -f "${MYCENTER_DEPLOYED_TEMPLATE_PATH}" ]] \
    || die "the deployed config template is missing"
  [[ -s "${MYCENTER_STATE_DIR}/current-image-tag" ]] \
    || die "the deployed image-tag record is missing"
  recorded_tag="$(tr -d '\r\n' < "${MYCENTER_STATE_DIR}/current-image-tag")"
  [[ "${recorded_tag}" =~ ^[0-9a-f]{7,40}$ ]] \
    || die "the deployed image-tag record is invalid"
  [[ -s "${MYCENTER_STATE_DIR}/releases/${recorded_tag}/docker-compose.yml" \
    && -s "${MYCENTER_STATE_DIR}/releases/${recorded_tag}/config.production.template.json" \
    && -s "${MYCENTER_STATE_DIR}/releases/${recorded_tag}/config.json" \
    && -x "${MYCENTER_STATE_DIR}/releases/${recorded_tag}/tools/backup.sh" \
    && -x "${MYCENTER_STATE_DIR}/releases/${recorded_tag}/tools/backup-recover.sh" \
    && -x "${MYCENTER_STATE_DIR}/releases/${recorded_tag}/tools/deploy.sh" \
    && -x "${MYCENTER_STATE_DIR}/releases/${recorded_tag}/tools/healthcheck.sh" \
    && -x "${MYCENTER_STATE_DIR}/releases/${recorded_tag}/tools/restore.sh" \
    && -x "${MYCENTER_STATE_DIR}/releases/${recorded_tag}/tools/update.sh" ]] \
    || die "the deployed release snapshot is incomplete"
  if [[ "${MYCENTER_ALLOW_PENDING_IMAGE_TAG:-0}" != "1" ]]; then
    [[ "${MYCENTER_IMAGE_TAG}" == "${recorded_tag}" ]] \
      || die "runtime image tag does not match the deployed tag record"
    cmp -s "${MYCENTER_STATE_DIR}/releases/${recorded_tag}/docker-compose.yml" \
      "${MYCENTER_DEPLOYED_COMPOSE_PATH}" \
      || die "the deployed Compose definition differs from the release snapshot"
    cmp -s "${MYCENTER_STATE_DIR}/releases/${recorded_tag}/config.production.template.json" \
      "${MYCENTER_DEPLOYED_TEMPLATE_PATH}" \
      || die "the deployed config template differs from the release snapshot"
    cmp -s "${MYCENTER_STATE_DIR}/releases/${recorded_tag}/config.json" \
      "${MYCENTER_CONFIG_PATH}" \
      || die "the runtime config differs from the release snapshot"
    [[ "$(readlink -f "${MYCENTER_TOOLS_LINK}" 2>/dev/null || true)" \
      == "$(readlink -f "${MYCENTER_STATE_DIR}/releases/${recorded_tag}/tools")" ]] \
      || die "the active maintenance tools differ from the release snapshot"
  else
    [[ "${MYCENTER_OPERATION_LOCK_HELD:-0}" == "1" ]] \
      || die "a pending image tag requires the inherited maintenance lock"
  fi
  [[ "${MYCENTER_SESSION_KEY}" =~ ^[0-9a-f]{96}$ ]] \
    || die "MYCENTER_SESSION_KEY must be a 96-character generated hex value"
  [[ "${MYCENTER_REGISTRATION_TOKEN}" =~ ^[0-9a-f]{64}$ ]] \
    || die "MYCENTER_REGISTRATION_TOKEN must be a 64-character guard"
  docker image inspect "mycenter:${MYCENTER_IMAGE_TAG}" >/dev/null 2>&1 \
    || die "the deployed versioned image is missing"
}

render_config() {
  local template tmp
  template="${MYCENTER_DEPLOYED_TEMPLATE_PATH}"
  if [[ ! -f "${template}" ]]; then
    template="${MYCENTER_SOURCE_DIR}/deploy/config.production.template.json"
  fi
  [[ -f "${template}" ]] || {
    echo "ERROR: missing production config template" >&2
    return 1
  }
  install -d -o root -g root -m 0750 \
    "${MYCENTER_DEPLOY_DIR}" "${MYCENTER_STATE_DIR}" "$(dirname "${MYCENTER_CONFIG_PATH}")" \
    || return 1
  tmp="$(mktemp "${MYCENTER_CONFIG_PATH}.tmp.XXXXXX")" || return 1
  if ! jq \
    --arg domain "${MYCENTER_DOMAIN}" \
    --arg email "${ACME_EMAIL}" \
    --argjson production "${ACME_PRODUCTION}" \
    --argjson new_accounts "${MYCENTER_NEW_ACCOUNTS}" \
    '.settings.cert = $domain
      | .settings.sessionKey = env.MYCENTER_SESSION_KEY
      | .domains[""].newAccounts = $new_accounts
      | .domains[""].newAccountsPass = env.MYCENTER_REGISTRATION_TOKEN
      | .letsEncrypt.email = $email
      | .letsEncrypt.names = $domain
      | .letsEncrypt.production = $production' \
    "${template}" > "${tmp}"; then
    rm -f -- "${tmp}"
    return 1
  fi
  if ! jq empty "${tmp}" >/dev/null; then
    rm -f -- "${tmp}"
    return 1
  fi
  if ! chown 10001:10001 "${tmp}" || ! chmod 0600 "${tmp}"; then
    rm -f -- "${tmp}"
    return 1
  fi
  mv -f -- "${tmp}" "${MYCENTER_CONFIG_PATH}" || {
    rm -f -- "${tmp}"
    return 1
  }
}

verify_source() {
  local agent_blob tool
  [[ -z "$(git -C "${MYCENTER_SOURCE_DIR}" status --porcelain)" ]] || die "source checkout is not clean"
  for agent_blob in MeshCmd.exe MeshCmd64.exe MeshService.exe MeshService64.exe; do
    git -C "${MYCENTER_SOURCE_DIR}" cat-file -e "HEAD:agents/${agent_blob}" \
      || die "tracked Windows agent blob is missing from HEAD: ${agent_blob}"
  done
  for tool in "${release_tool_names[@]}"; do
    [[ -f "${MYCENTER_SOURCE_DIR}/deploy/${tool}" ]] \
      || die "required maintenance tool is missing: ${tool}"
  done
}

verify_fresh_runtime() {
  local resource
  if docker container inspect mycenter >/dev/null 2>&1; then
    die "an existing mycenter container requires manual review"
  fi
  for resource in meshcentral-data meshcentral-files meshcentral-web meshcentral-backups; do
    if docker volume inspect "${resource}" >/dev/null 2>&1; then
      die "an existing Docker volume requires manual review: ${resource}"
    fi
  done
  if docker network inspect mycenter_default >/dev/null 2>&1; then
    die "an existing mycenter_default network requires manual review"
  fi
}

initial_deploy() {
  [[ ! -e /var/run/reboot-required ]] \
    || die "the VPS requires a reboot before the initial deployment"
  [[ "${ACME_PRODUCTION}" == "false" ]] \
    || die "the initial deployment must use ACME staging"
  [[ "${MYCENTER_NEW_ACCOUNTS}" == "false" ]] \
    || die "public registration must remain closed during ACME staging"
  [[ "${MYCENTER_BOOTSTRAP_ACTIVE}" == "true" ]] \
    || die "the initial deployment requires an active protected bootstrap"
  check_dns
  verify_source
  verify_fresh_runtime
  prepare_initial_runtime_values
  install_deployed_template "${MYCENTER_SOURCE_DIR}/deploy/config.production.template.json"
  COMPOSE_FILE_OVERRIDE="${MYCENTER_SOURCE_DIR}/deploy/docker-compose.yml"
  render_config

  compose config --quiet
  compose build --pull mycenter
  install_deployed_compose "${MYCENTER_SOURCE_DIR}/deploy/docker-compose.yml"
  record_release_files "${MYCENTER_IMAGE_TAG}"
  record_release_tools "${MYCENTER_IMAGE_TAG}" "${MYCENTER_SOURCE_DIR}/deploy"
  activate_release_tools "${MYCENTER_IMAGE_TAG}"
  COMPOSE_FILE_OVERRIDE="${MYCENTER_DEPLOYED_COMPOSE_PATH}"
  compose config --quiet
  docker volume create \
    --label com.mycenter.purpose=backups \
    meshcentral-backups >/dev/null
  compose up -d --no-build --force-recreate mycenter
  wait_for_health 120 || die "MyCenter failed its container healthcheck"
  verify_runtime_restart_policy || die "MyCenter restart policy is not unless-stopped"

  wait_for_acme_files staging 120 \
    || die "ACME staging certificate files were not created"

  record_current_image_tag
  systemctl enable --now mycenter.service
  wait_for_health 120 || die "MyCenter failed after enabling boot reconciliation"
  verify_runtime_restart_policy || die "boot reconciliation changed the restart policy"

  echo "MyCenter is running with ACME staging enabled."
  echo "After staging succeeds, run: ${MYCENTER_TOOLS_LINK}/deploy.sh --promote-acme"
}

attempt_production_acme() {
  compose stop --timeout 45 mycenter || return 1
  docker run --rm \
    --network none \
    --user 10001:10001 \
    --volume meshcentral-data:/data \
    --entrypoint /bin/sh \
    "mycenter:${MYCENTER_IMAGE_TAG}" \
    -c 'rm -f -- /data/letsencrypt-certs/staging.crt /data/letsencrypt-certs/staging.key' \
    || return 1

  set_env_value ACME_PRODUCTION true || return 1
  load_env || return 1
  render_config || return 1
  compose up -d --no-build --force-recreate mycenter || return 1
  wait_for_health 180 || return 1
  verify_runtime_restart_policy || return 1
  wait_for_acme_files production 120 || return 1
  curl --fail --silent --show-error \
    --noproxy "${MYCENTER_DOMAIN}" \
    --connect-timeout 5 \
    --max-time 15 \
    --resolve "${MYCENTER_DOMAIN}:443:127.0.0.1" \
    "https://${MYCENTER_DOMAIN}/health.ashx" | grep -Fxq ok \
    || return 1
}

restore_staging_mode() {
  set_env_value ACME_PRODUCTION false || return 1
  load_env || return 1
  render_config || return 1
  compose up -d --no-build --force-recreate mycenter || return 1
  wait_for_health 120 || return 1
  verify_runtime_restart_policy || return 1
  wait_for_acme_files staging 120 || return 1
}

rollback_acme_failure() {
  local exit_code="${1:-1}" recovery_status
  [[ "${exit_code}" -ne 0 ]] || exit_code=1
  trap - ERR INT TERM EXIT
  set +e
  echo "Production ACME failed; returning to staging mode..." >&2
  restore_staging_mode
  recovery_status=$?
  if [[ "${recovery_status}" -eq 0 ]]; then
    echo "Production ACME failed; staging mode was restored." >&2
  else
    echo "Production ACME failed and automatic staging recovery also failed." >&2
  fi
  exit "${exit_code}"
}

promote_acme() {
  [[ "${ACME_PRODUCTION}" == "false" ]] || die "ACME_PRODUCTION is already true"
  [[ "${MYCENTER_NEW_ACCOUNTS}" == "false" ]] \
    || die "public registration must be closed during ACME promotion"
  [[ "${MYCENTER_BOOTSTRAP_ACTIVE}" == "true" ]] \
    || die "the first-administrator bootstrap is already closed"
  [[ "${MYCENTER_REGISTRATION_TOKEN}" =~ ^[0-9a-f]{64}$ ]] \
    || die "the protected first-account token is missing"
  check_dns
  compose exec -T mycenter test -s /opt/meshcentral/meshcentral-data/letsencrypt-certs/staging.crt \
    || die "staging certificate has not been created"
  compose exec -T mycenter test -s /opt/meshcentral/meshcentral-data/letsencrypt-certs/staging.key \
    || die "staging key has not been created"

  trap 'rollback_acme_failure "$?"' ERR INT TERM EXIT
  attempt_production_acme
  record_release_files "${MYCENTER_IMAGE_TAG}"
  trap - ERR INT TERM EXIT

  echo "Production ACME certificate is active and trusted for ${MYCENTER_DOMAIN}."
}

release_operation_lock() {
  [[ "${OPERATION_LOCK_OWNED}" == "1" ]] \
    || die "this action requires a directly acquired maintenance lock"
  flock -u 9
  exec 9>&-
  OPERATION_LOCK_OWNED=0
}

enable_backups() {
  [[ "${ACME_PRODUCTION}" == "true" ]] \
    || die "backups may be enabled only after production ACME succeeds"
  [[ "${MYCENTER_NEW_ACCOUNTS}" == "false" ]] \
    || die "close public account registration before enabling backups"
  [[ "${MYCENTER_BOOTSTRAP_ACTIVE}" == "false" ]] \
    || die "close the first-account bootstrap before enabling backups"
  [[ "${MYCENTER_REGISTRATION_TOKEN}" =~ ^[0-9a-f]{64}$ ]] \
    || die "the permanent registration guard is missing"
  wait_for_health 120 || die "MyCenter must be healthy before enabling backups"
  MYCENTER_OPERATION_LOCK_HELD=1 "${MYCENTER_TOOLS_LINK}/backup.sh"
  MYCENTER_OPERATION_LOCK_HELD=1 "${MYCENTER_TOOLS_LINK}/restore.sh" --dry-run
  systemctl enable mycenter-backup.timer
  release_operation_lock
  systemctl start mycenter-backup.timer
  echo "Initial backup and restore dry-run passed; the daily backup timer is enabled."
}

close_registration() {
  [[ "${CLOSE_CONFIRMATION}" == "ADMIN_CREATED" ]] \
    || die "closing the bootstrap token requires: --close-registration ADMIN_CREATED"
  if [[ "${MYCENTER_BOOTSTRAP_ACTIVE}" == "true" ]]; then
    set_env_value MYCENTER_REGISTRATION_TOKEN "$(openssl rand -hex 32)" \
      || die "unable to rotate the first-account token"
    set_env_value MYCENTER_BOOTSTRAP_ACTIVE false \
      || die "unable to persist the closed bootstrap state"
  fi
  set_env_value MYCENTER_NEW_ACCOUNTS false \
    || die "unable to persist closed registration"
  load_env
  render_config
  compose up -d --no-build --force-recreate mycenter
  wait_for_health 120 || die "MyCenter failed while enforcing closed registration"
  verify_runtime_restart_policy || die "MyCenter restart policy is not unless-stopped"
  record_release_files "${MYCENTER_IMAGE_TAG}"
  echo "Public account registration is disabled and protected by an unrevealed guard."
}

require_root
load_env
validate_values
if [[ "${MYCENTER_OPERATION_LOCK_HELD:-0}" != "1" ]]; then
  exec 9>"${OPERATION_LOCK_FILE}"
  flock -n 9 || die "another MyCenter maintenance operation is already running"
  OPERATION_LOCK_OWNED=1
else
  inherited_lock="$(readlink -f "/proc/$$/fd/9" 2>/dev/null || true)"
  [[ "${inherited_lock}" == "${OPERATION_LOCK_FILE}" ]] \
    || die "invalid inherited MyCenter maintenance lock"
  flock -n 9 || die "the inherited MyCenter maintenance lock is not held"
fi

# Reload after taking the lock so a completed concurrent maintenance action
# cannot leave this process using stale runtime values.
load_env
validate_values

if [[ -e "${MYCENTER_MAINTENANCE_MARKER}" \
  && !( "${ACTION}" == "--render-only" \
    && "${MYCENTER_ALLOW_PENDING_IMAGE_TAG:-0}" == "1" \
    && "${MYCENTER_OPERATION_LOCK_HELD:-0}" == "1" ) ]]; then
  die "incomplete destructive maintenance requires manual recovery"
fi
[[ ! -e /run/mycenter-backup-restart-needed ]] \
  || die "an interrupted backup requires recovery before another maintenance action"
if docker container inspect mycenter-backup-worker >/dev/null 2>&1; then
  die "a stale backup helper container requires recovery"
fi

case "${ACTION}" in
  deploy)
    initial_deploy
    ;;
  --render-only)
    require_deployed_runtime_values
    render_config
    ;;
  --promote-acme)
    require_deployed_runtime_values
    promote_acme
    ;;
  --close-registration)
    require_deployed_runtime_values
    close_registration
    ;;
  --enable-backups)
    require_deployed_runtime_values
    enable_backups
    ;;
  *)
    die "usage: $0 [deploy|--render-only|--promote-acme|--close-registration ADMIN_CREATED|--enable-backups]"
    ;;
esac
