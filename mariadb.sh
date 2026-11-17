#!/bin/bash
set -euo pipefail
umask 077
data_dir="${HOME}/.oma/mysql"
mkdir -p "${data_dir}"
if [ ! -d "${data_dir}/mysql" ]; then
    mariadb-install-db --no-defaults --datadir="${data_dir}" \
        --auth-root-authentication-method=socket --auth-root-socket-user=node \
        --skip-test-db >/dev/null
fi
# One small test site per instance. Increase these limits only after measuring load.
exec mariadbd --no-defaults --datadir="${data_dir}" \
    --socket=/tmp/oma-mariadb.sock --pid-file=/tmp/oma-mariadb.pid \
    --skip-networking --skip-log-bin --innodb-buffer-pool-size=128M \
    --max-connections=20 --performance-schema=OFF
