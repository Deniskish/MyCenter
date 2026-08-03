#!/bin/sh
set -eu

# Keep newly generated databases, keys, certificates and runtime metadata
# owner-only unless MeshCentral explicitly selects a different mode.
umask 077

exec node meshcentral.js
