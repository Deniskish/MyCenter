# syntax=docker/dockerfile:1.7

FROM node:24-bookworm-slim AS dependencies

WORKDIR /opt/meshcentral/meshcentral

COPY package.json package-lock.json ./

# MeshCentral has no development dependency section in this checkout. The
# optional modules below are existing upstream runtime features enabled by the
# production configuration: ACME and common-password blocking.
RUN npm ci --omit=dev \
    && npm install --no-save --package-lock=false --omit=dev \
        acme-client@4.2.5 \
        wildleek@2.0.0 \
    && npm cache clean --force

COPY . ./

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
COPY --chmod=0755 deploy/healthcheck.sh /usr/local/bin/mycenter-healthcheck
COPY --chmod=0755 deploy/container-entrypoint.sh /usr/local/bin/mycenter-entrypoint

WORKDIR /opt/meshcentral/meshcentral

EXPOSE 80 443

USER ${MYCENTER_UID}:${MYCENTER_GID}

# MeshCentral handles SIGINT by running its normal Stop() path.
STOPSIGNAL SIGINT

ENTRYPOINT ["/usr/local/bin/mycenter-entrypoint"]
