#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -z "${MYCENTER_DOMAIN:-}" ]]; then
  env_file="${MYCENTER_ENV_FILE:-/opt/mycenter/deploy/.env}"
  [[ -f "${env_file}" ]] || {
    echo "MYCENTER_DOMAIN is required and ${env_file} is unavailable" >&2
    exit 2
  }
  [[ "$(stat -c '%a' "${env_file}")" == "600" ]] || {
    echo "${env_file} must have mode 600" >&2
    exit 2
  }
  [[ "$(stat -c '%u' "${env_file}")" == "0" ]] || {
    echo "${env_file} must be owned by root" >&2
    exit 2
  }
  # The file is validated before it is sourced and values are never printed.
  set -a
  # shellcheck disable=SC1090
  source "${env_file}"
  set +a
fi

domain="${MYCENTER_DOMAIN:?MYCENTER_DOMAIN is required}"
production="${ACME_PRODUCTION:-false}"

case "${production,,}" in
  true)
    body="$({
      curl --fail --silent --show-error \
        --noproxy "${domain}" \
        --connect-timeout 5 \
        --max-time 8 \
        --resolve "${domain}:443:127.0.0.1" \
        "https://${domain}/health.ashx"
    })"
    [[ "${body}" == "ok" ]]
    ;;
  false)
    # A Let's Encrypt staging certificate is deliberately not publicly trusted.
    # Check the HTTP redirect and that TCP/443 accepts connections; never use -k.
    status="$({
      curl --silent --show-error \
        --noproxy '*' \
        --connect-timeout 5 \
        --max-time 8 \
        --output /dev/null \
        --write-out '%{http_code}' \
        http://127.0.0.1:80/health.ashx
    })"
    case "${status}" in
      301|302|307|308) ;;
      *) exit 1 ;;
    esac

    node -e '
      const net = require("net");
      const socket = net.connect({ host: "127.0.0.1", port: 443 });
      const timer = setTimeout(() => { socket.destroy(); process.exit(1); }, 5000);
      socket.once("connect", () => { clearTimeout(timer); socket.destroy(); process.exit(0); });
      socket.once("error", () => { clearTimeout(timer); process.exit(1); });
    '
    ;;
  *)
    echo "ACME_PRODUCTION must be true or false" >&2
    exit 2
    ;;
esac
