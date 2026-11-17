"""Initialize a single local test site, then run Apache as the unprivileged user."""

import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import time
from urllib.parse import urlsplit


STATE = Path.home() / ".oma"
SITE = STATE / "wordpress"
SOCKET = "/tmp/oma-mariadb.sock"


def run(args, *, input=None, check=True):
    # Never include stdin or captured output in exceptions: these can contain secrets.
    result = subprocess.run(args, input=input, text=True, capture_output=True)
    if check and result.returncode:
        raise RuntimeError(f"{args[0]} {args[1]} failed (exit {result.returncode})")
    return result


def wp(*args, **kwargs):
    return run(["/usr/local/bin/wp", f"--path={SITE}", *args], **kwargs)


def initialize():
    url = os.environ.get("OMA_WORDPRESS_URL", "http://localhost:8081").rstrip("/")
    parsed = urlsplit(url)
    if parsed.scheme not in ("http", "https") or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError("OMA_WORDPRESS_URL must be an absolute HTTP(S) URL without credentials")

    STATE.mkdir(mode=0o700, parents=True, exist_ok=True)
    credentials_path = STATE / "wordpress-credentials.json"
    if not credentials_path.exists():
        credentials = {
            "username": "oma",
            "password": secrets.token_urlsafe(32),
            "database_password": secrets.token_hex(32),
        }
        # Publish the complete file atomically so an interrupted boot cannot leave
        # truncated credentials next to an already initialized database.
        temporary = credentials_path.with_suffix(".tmp")
        with temporary.open("w", encoding="utf-8") as stream:
            os.chmod(temporary, 0o600)
            json.dump(credentials, stream)
        temporary.replace(credentials_path)
    credentials = json.loads(credentials_path.read_text())

    for _ in range(120):
        if run(["mariadb", "--no-defaults", f"--socket={SOCKET}", "--user=node", "-e", "SELECT 1"], check=False).returncode == 0:
            break
        time.sleep(1)
    else:
        raise RuntimeError("MariaDB did not become ready within 120 seconds")

    # Generated hex only; validate before interpolating into SQL on subsequent boots.
    database_password = credentials["database_password"]
    if len(database_password) != 64 or any(c not in "0123456789abcdef" for c in database_password):
        raise ValueError("Invalid persisted database password")
    run(["mariadb", "--no-defaults", f"--socket={SOCKET}", "--user=node"], input=f"""
CREATE DATABASE IF NOT EXISTS wordpress CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'wordpress'@'localhost' IDENTIFIED BY '{database_password}';
GRANT ALL PRIVILEGES ON wordpress.* TO 'wordpress'@'localhost';
""")

    if not (SITE / "wp-includes/version.php").exists():
        shutil.copytree("/opt/oma/wordpress", SITE, dirs_exist_ok=True)
    if not (SITE / "wp-config.php").exists():
        constants = {
            "DB_NAME": "wordpress", "DB_USER": "wordpress",
            "DB_PASSWORD": database_password, "DB_HOST": f"localhost:{SOCKET}",
            "DB_CHARSET": "utf8mb4", "DB_COLLATE": "",
        }
        for name in ("AUTH_KEY", "SECURE_AUTH_KEY", "LOGGED_IN_KEY", "NONCE_KEY",
                     "AUTH_SALT", "SECURE_AUTH_SALT", "LOGGED_IN_SALT", "NONCE_SALT"):
            constants[name] = secrets.token_hex(32)
        # All values above are fixed literals or generated hex, never user-supplied PHP.
        config = "<?php\n" + "".join(f"define('{key}', '{value}');\n" for key, value in constants.items())
        config += """
// Agent37's authenticated edge is the trusted HTTPS proxy for this test site.
if (($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https') {
    $_SERVER['HTTPS'] = 'on';
}
define('DISALLOW_FILE_EDIT', true);
$table_prefix = 'wp_';
define('ABSPATH', __DIR__ . '/');
require_once ABSPATH . 'wp-settings.php';
"""
        temporary = SITE / "wp-config.php.tmp"
        temporary.write_text(config)
        os.chmod(temporary, 0o600)
        temporary.replace(SITE / "wp-config.php")

    if wp("core", "is-installed", check=False).returncode:
        wp("core", "install", f"--url={url}", "--title=OMA Test Site",
           f"--admin_user={credentials['username']}", "--admin_email=admin@example.invalid",
           "--skip-email", "--prompt=admin_password", input=credentials["password"] + "\n")
        wp("rewrite", "structure", "/%postname%/")
        wp("option", "update", "blog_public", "0")
    print("[oma] WordPress ready on :8081; credentials: ~/.oma/wordpress-credentials.json", flush=True)


if __name__ == "__main__":
    os.umask(0o077)
    initialize()
    os.execv("/usr/sbin/apache2", ["apache2", "-f", "/opt/oma/apache2.conf", "-DFOREGROUND"])
