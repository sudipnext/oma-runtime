"""Give Supervisor reopenable output pipes on Agent37's unprivileged VM runner."""

import signal
import subprocess
import sys


# Agent37 hands node root-owned stdout/stderr pipes. Inherited writes work, but
# Supervisor's child loggers cannot reopen /dev/stdout. A pipe created as node
# fixes ownership without making the application or its services run as root.
with subprocess.Popen(
    ["/usr/bin/supervisord", "-n", "-c", "/opt/oma/supervisord.conf"],
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
) as process:
    for signum in (signal.SIGTERM, signal.SIGINT):
        signal.signal(signum, lambda received, _frame: process.send_signal(received))
    while chunk := process.stdout.read1(65536):
        sys.stdout.buffer.write(chunk)
        sys.stdout.buffer.flush()
    sys.exit(process.wait())
