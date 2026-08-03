#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DIR="${MYCENTER_SOURCE_DIR:-/opt/mycenter/src}"
DEPLOY_DIR="${MYCENTER_DEPLOY_DIR:-/opt/mycenter/deploy}"
STATE_DIR="${MYCENTER_STATE_DIR:-/opt/mycenter/state}"
TIMEZONE="${MYCENTER_TIMEZONE:-UTC}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ "${EUID}" -eq 0 ]] || die "run this script as root"
[[ -r /etc/os-release ]] || die "unable to identify the operating system"

# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID}" == "ubuntu" && "${VERSION_ID}" == "24.04" ]] \
  || die "Ubuntu Server 24.04 LTS is required"
[[ "$(dpkg --print-architecture)" == "amd64" ]] \
  || die "x86_64/amd64 is required"
[[ -d "${SOURCE_DIR}/.git" ]] || die "source checkout is missing at ${SOURCE_DIR}"
if find "${SOURCE_DIR}" -xdev ! -user root -print -quit | grep -q .; then
  die "the production source checkout must be owned entirely by root"
fi
if find "${SOURCE_DIR}" -xdev -perm /022 -print -quit | grep -q .; then
  die "the production source checkout must not be group- or world-writable"
fi

echo "Operating system: ${PRETTY_NAME}"
echo "Architecture: $(dpkg --print-architecture)"
echo "Hostname: $(hostname --fqdn 2>/dev/null || hostname)"
echo "Memory:"
free -h
echo "Disk space:"
df -h /
echo "Swap:"
swapon --show || true
echo "Listening sockets before installation:"
ss -lntup || true

if ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -Eq '(^|:)(80|443)$'; then
  die "port 80 or 443 is already occupied; no service was changed"
fi

for container_command in docker dockerd containerd ctr podman; do
  if command -v "${container_command}" >/dev/null 2>&1; then
    die "${container_command} is already installed; inspect the existing container stack before changing it"
  fi
done

for storage_path in /var/lib/docker /var/lib/containerd; do
  if [[ -d "${storage_path}" ]] \
    && find "${storage_path}" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
    die "existing container storage requires manual review: ${storage_path}"
  fi
done

for unit_path in \
  /etc/systemd/system/docker.service \
  /etc/systemd/system/containerd.service \
  /usr/local/lib/systemd/system/docker.service \
  /usr/local/lib/systemd/system/containerd.service; do
  [[ ! -e "${unit_path}" ]] \
    || die "existing container service unit requires manual review: ${unit_path}"
done

conflicting_packages=()
for package_name in \
  docker.io docker-compose docker-compose-v2 docker-doc podman-docker \
  containerd runc containerd.io docker-ce docker-ce-cli \
  docker-buildx-plugin docker-compose-plugin; do
  if dpkg-query -W -f='${db:Status-Abbrev}' "${package_name}" 2>/dev/null | grep -q '^ii '; then
    conflicting_packages+=("${package_name}")
  fi
done
if (( ${#conflicting_packages[@]} > 0 )); then
  die "conflicting container packages are installed: ${conflicting_packages[*]}"
fi

[[ ! -e /etc/apt/sources.list.d/docker.sources ]] \
  || die "existing Docker apt source requires manual review"
[[ ! -e /etc/apt/sources.list.d/docker.list ]] \
  || die "existing Docker apt source requires manual review"
if grep -Rqs 'download\.docker\.com/linux/ubuntu' \
  /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
  die "an existing Docker apt source requires manual review"
fi
[[ ! -e /etc/apt/keyrings/docker.asc ]] \
  || die "an existing Docker signing key requires manual review"

for managed_path in \
  /etc/systemd/journald.conf.d/mycenter.conf \
  /etc/apt/apt.conf.d/52mycenter-periodic \
  /etc/systemd/system/mycenter.service \
  /etc/systemd/system/mycenter-backup.service \
  /etc/systemd/system/mycenter-backup.timer; do
  [[ ! -e "${managed_path}" ]] \
    || die "an existing MyCenter-managed file requires manual review: ${managed_path}"
done

timedatectl list-timezones | grep -Fxq "${TIMEZONE}" \
  || die "invalid MYCENTER_TIMEZONE: ${TIMEZONE}"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  dnsutils \
  git \
  jq \
  openssl \
  unattended-upgrades \
  ufw

# Apply configured Ubuntu security updates without enabling a release upgrade.
unattended-upgrade --debug \
  || die "unattended-upgrade failed; inspect its logs before continuing"

install -d -m 0755 /etc/apt/keyrings
docker_key_tmp="$(mktemp)"
trap 'rm -f -- "${docker_key_tmp}"' EXIT
curl --fail --silent --show-error --location \
  https://download.docker.com/linux/ubuntu/gpg > "${docker_key_tmp}"
install -o root -g root -m 0644 "${docker_key_tmp}" /etc/apt/keyrings/docker.asc

cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt-get update
apt-get install -y --no-install-recommends \
  containerd.io \
  docker-buildx-plugin \
  docker-ce \
  docker-ce-cli \
  docker-compose-plugin
systemctl enable --now docker

install -d -o root -g root -m 0750 /opt/mycenter "${DEPLOY_DIR}" "${STATE_DIR}"
install -d -o root -g root -m 0700 /opt/mycenter/restore-tmp

timedatectl set-timezone "${TIMEZONE}"

install -d -o root -g root -m 0755 /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/mycenter.conf <<'EOF'
[Journal]
SystemMaxUse=1G
MaxRetentionSec=30day
Compress=yes
EOF
systemctl restart systemd-journald

cat > /etc/apt/apt.conf.d/52mycenter-periodic <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
systemctl enable --now apt-daily.timer apt-daily-upgrade.timer unattended-upgrades.service

install -o root -g root -m 0644 \
  "${SOURCE_DIR}/deploy/mycenter.service" \
  /etc/systemd/system/mycenter.service
install -o root -g root -m 0644 \
  "${SOURCE_DIR}/deploy/mycenter-backup.service" \
  /etc/systemd/system/mycenter-backup.service
install -o root -g root -m 0644 \
  "${SOURCE_DIR}/deploy/mycenter-backup.timer" \
  /etc/systemd/system/mycenter-backup.timer
systemctl daemon-reload

ssh_port="$(sshd -T 2>/dev/null | awk '$1 == "port" { print $2; exit }')"
ssh_port="${ssh_port:-22}"

echo
echo "Docker installation completed."
docker --version
docker compose version
echo
echo "UFW was installed but NOT enabled. Detected SSH port: ${ssh_port}."
echo "Before enabling UFW, open a second key-authenticated SSH session and follow deploy/README.md."
echo "The boot reconciliation unit and backup timer are installed but remain disabled until their deployment gates succeed."
if [[ -e /var/run/reboot-required ]]; then
  echo "WARNING: the VPS requires a reboot before production deployment." >&2
fi
