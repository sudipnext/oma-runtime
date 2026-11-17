#!/bin/bash
set -euo pipefail
umask 077
mkdir -p "${HOME}/.oma"
exec /usr/bin/supervisord -n -c /opt/oma/supervisord.conf
