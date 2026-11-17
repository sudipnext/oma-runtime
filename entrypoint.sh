#!/bin/bash
set -euo pipefail
umask 077
mkdir -p "${HOME}/.oma"
exec /usr/bin/python3 /opt/oma/supervise.py
