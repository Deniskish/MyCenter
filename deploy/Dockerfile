# syntax=docker/dockerfile:1.7

FROM node:24-bookworm-slim AS dependencies

WORKDIR /opt/meshcentral/meshcentral

COPY package.json package-lock.json ./

# MeshCentral has no development dependency section in this checkout.
# Optional runtime modules used by the production configuration.
RUN npm ci --omit=dev \
    && npm install --no-save --package-lock=false --omit=dev \
       acme-client@4.2.5 \
       wildleek@2.0.0 \
    && npm cache clean --force

COPY . ./

# Obtain pristine upstream Windows agent binaries.
# This avoids broken/zero-length EXE files caused by antivirus quarantine
# or damaged files in the local checkout.
FROM node:24-bookworm-slim AS upstream-agents

WORKDIR /tmp

RUN set -eux; \
    archive="$(npm pack meshcentral@1.2.4 --silent)"; \
    tar -xzf "${archive}"; \
    for f in \
      MeshCmd.exe \
      MeshCmd64.exe \
      MeshService.exe \
      MeshService64.exe; do \
        test -s "/tmp/package/agents/${f}"; \
        header="$(od -An -tx1 -N2 "/tmp/package/agents/${f}" | tr -d ' \n')"; \
        test "${header}" = "4d5a"; \
    done

FROM node:24-bookworm-slim AS runtime

ARG MYCENTER_UID=10001
ARG MYCENTER_GID=10001

ENV NODE_ENV=production

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates \
       coreutils \
       curl \
       findutils \
       tar \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid "${MYCENTER_GID}" mycenter \
    && useradd --uid "${MYCENTER_UID}" --gid "${MYCENTER_GID}" \
       --home-dir /nonexistent --no-create-home --shell /usr/sbin/nologin mycenter \
    && install -d -o "${MYCENTER_UID}" -g "${MYCENTER_GID}" -m 0750 \
       /opt/meshcentral/meshcentral \
       /opt/meshcentral/meshcentral-data \
       /opt/meshcentral/meshcentral-files \
       /opt/meshcentral/meshcentral-web \
       /opt/meshcentral/meshcentral-backups

COPY --from=dependencies --chown=${MYCENTER_UID}:${MYCENTER_GID} \
     /opt/meshcentral/meshcentral /opt/meshcentral/meshcentral

# Always overwrite these four files with verified upstream binaries.
COPY --from=upstream-agents --chown=${MYCENTER_UID}:${MYCENTER_GID} --chmod=0755 \
     /tmp/package/agents/MeshCmd.exe \
     /tmp/package/agents/MeshCmd64.exe \
     /tmp/package/agents/MeshService.exe \
     /tmp/package/agents/MeshService64.exe \
     /opt/meshcentral/meshcentral/agents/

COPY --chmod=0755 deploy/healthcheck.sh /usr/local/bin/mycenter-healthcheck
COPY --chmod=0755 deploy/container-entrypoint.sh /usr/local/bin/mycenter-entrypoint

WORKDIR /opt/meshcentral/meshcentral

EXPOSE 80 443

USER ${MYCENTER_UID}:${MYCENTER_GID}

STOPSIGNAL SIGINT

ENTRYPOINT ["/usr/local/bin/mycenter-entrypoint"]