# OMA runtime

An experimental, single-instance image containing Hermes and a **local WordPress test site** for Open Marketing Agency. Source: [sudipnext/oma-runtime](https://github.com/sudipnext/oma-runtime). Package: [GHCR](https://github.com/sudipnext/oma-runtime/pkgs/container/oma-runtime).

The image extends Agent37's pinned `hermes-base:2026.11.12b` (Hermes v0.23.1) with WordPress 7.1.4, WP-CLI 2.12.0, Apache/PHP 8.2 and MariaDB. Official WordPress and WP-CLI downloads are verified with SHA-256. The upstream Hermes entrypoint still manages its gateway, browser, terminal and file services; Supervisor manages that entrypoint alongside the two CMS services. Everything runs as `node` (UID 1000).

The 4 GB / 2 CPU starting point uses four PHP workers and a 128 MB MariaDB buffer pool. CI boots it under those limits. This verifies boot and persistence, not capacity for concurrent browser sessions or a full specialist roster. Measure real mission workloads before increasing concurrency.

## Build and test

```bash
docker build --platform linux/amd64 -t oma-runtime:test .
bash smoke-test.sh oma-runtime:test
```

The smoke test starts with an empty home volume, checks Hermes and WordPress, blocks access to `wp-config.php` and uploaded PHP, writes a post and a Hermes skill, then recreates the container against the same volume. The second boot reproduces Agent37 VM output pipes owned by root before dropping to `node`; the output relay preserves non-root service logging. It checks the post, skill, database value, credentials and permalink survived. It removes only its own temporary containers and volume.

Run locally with loopback-only bindings; the inherited terminal and file browser rely on Agent37's authenticated edge:

```bash
docker run -d --name oma-experiment --memory=4g --cpus=2 \
  --mount source=oma-experiment-home,target=/home/node \
  -p 127.0.0.1:8081:8081 -p 127.0.0.1:3737:3737 \
  oma-runtime:test
docker logs -f oma-experiment
```

WordPress starts at `http://localhost:8081`, with search indexing discouraged. A random admin password and database password are generated per instance and stored mode `0600` at `~/.oma/wordpress-credentials.json`. Retrieve the admin credential through authenticated exec or your local terminal; it is never printed in startup logs:

```bash
docker exec oma-experiment python3 -c \
  'import json,pathlib; c=json.loads((pathlib.Path.home()/".oma/wordpress-credentials.json").read_text()); print(c["username"], c["password"])'
```

## Publish

GitHub Actions builds `linux/amd64`, runs the smoke test, and only then pushes the **same tested image**. Main publishes `latest` and `sha-<full-commit>`; `v*` tags additionally publish the release tag. Pull requests test without publishing. Publishing uses the repository's built-in `GITHUB_TOKEN` with `packages: write`; no registry credential belongs in the source or Dockerfile.

After the first publish, set the GHCR package visibility to **Public** in its package settings and verify an anonymous pull. A public repository does not by itself make its package public. Use `ghcr.io/sudipnext/oma-runtime:sha-<full-commit>` or the returned digest for Agent37, rather than `latest`.

## Register with Agent37

Run these commands from an administrator's machine or the control plane. Keep `AGENT37_API_KEY` there, never in an agent image or instance. Set `OMA_IMAGE` to a published commit tag or digest:

```bash
export OMA_IMAGE=ghcr.io/sudipnext/oma-runtime:sha-<full-commit>
python3 - <<'PY' > /tmp/oma-template.json
import json, os
print(json.dumps({"name": "oma-runtime", "image_ref": os.environ["OMA_IMAGE"]}))
PY
curl --fail-with-body https://api.agent37.com/v1/templates \
  -H "Authorization: Bearer $AGENT37_API_KEY" \
  -H 'Content-Type: application/json' --data-binary @/tmp/oma-template.json
```

Registration copies the image and returns an immutable template revision/digest. Re-pushing a tag does not update an existing template or instance. For an existing template, use `PATCH /v1/templates/oma-runtime` with a new image reference.

To request a **real VM** with 2 CPU / 4 GB RAM / 12 GB disk (this incurs Agent37 usage), use the returned template revision in place of `<revision>`:

```bash
curl --fail-with-body https://api.agent37.com/v1/instances \
  -H "Authorization: Bearer $AGENT37_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"name":"OMA experiment","template":"oma-runtime@<revision>","type":"vm","resources":{"cpu":2,"memory":4,"disk":12},"auto_sleep":false}'
```

Agent37's cheaper `default` type is a sandbox; `vm` has its own kernel. Their compute rates differ. This repository does not automatically provision either.

Leave the template default port at **3737** for the chat gateway. WordPress uses **8081**, Hermes dashboard **9119**, terminal **7681**, and file browser **8080**. Obtain authenticated/signed access through Agent37; do not publish the terminal, dashboard or file browser as public ports.

After create, use authenticated [exec](https://www.agent37.com/docs/agents-api/exec) to set WordPress's canonical address to `https://<instance-id>-8081.agent37.app` (or a permanent public site URL if you deliberately publish the test site). In the instance:

```bash
wp --path="$HOME/.oma/wordpress" option update home 'https://<instance-id>-8081.agent37.app'
wp --path="$HOME/.oma/wordpress" option update siteurl 'https://<instance-id>-8081.agent37.app'
```

Do not store a short-lived signed URL as the canonical address. For a known URL at first boot, supply `env: {"OMA_WORDPRESS_URL": "https://your-test-site.example"}` in the create request. Later boots preserve the database's URL and password rather than resetting them. Agent37 terminates TLS; WordPress honors the edge's `X-Forwarded-Proto: https` header. Local deployments should likewise sit behind a trusted proxy if exposed.

## Model and playbook bootstrap

The clean Hermes base deliberately has **no model provider or managed integration configuration**. Configure the deployment's scoped LiteLLM credential (or your chosen provider) in `~/.hermes/config.yaml` through authenticated provisioning. Keep LiteLLM master keys and provider administration keys outside the instance. A gateway HTTP response alone does not prove that inference works.

Install the selected OMA personas, profile configurations and skills onto the persistent home **after create**, then start the mission and verify a real model turn. No customer mission, provider secret or fixed playbook is baked into this shared image. The rough architecture in the OMA source repository remains a proposal; this image does not implement its deployment resolver, budgets or coordinator lifecycle.

## State, logs and updates

Persist all of `/home/node`: Hermes state lives in `~/.hermes`, WordPress in `~/.oma/wordpress`, MariaDB in `~/.oma/mysql`, and credentials in `~/.oma/wordpress-credentials.json`. MariaDB has no TCP listener. Stop the instance before taking a filesystem copy of its database, or use `mariadb-dump` for a live logical backup.

Supervisor and all services write to stdout/stderr. The future dashboard can read them with `GET https://sandbox.agent37.app/v1/instances/<id>/logs?tail=200` and `X-Agent37-Key`. Logs work even for stopped/failed instances; fetch the instance's `status_reason` too when no container started. Boot logs and workload output must stay behind the owning user's authorization in the control plane.

Image updates preserve the existing site's files, plugins, database and credentials. They do **not** overwrite or automatically upgrade an existing WordPress installation. Back up the site and apply WordPress upgrades deliberately with WP-CLI. Rebuild this image to update its pinned Hermes base and seed versions.

The local CMS shares the agent's Unix account and is for experimentation. For customer production sites, use separately managed WordPress/database infrastructure, backups and narrower CMS credentials. A future deployment dashboard should extend OMA's existing FastAPI/Next.js stack with owner-scoped deployment records, durable provisioning, lifecycle operations, signed URLs and logs; no second control plane is included here.

Contract references: [custom images](https://www.agent37.com/docs/agents-api/custom-image), [templates](https://www.agent37.com/docs/agents-api/templates), [instance create](https://www.agent37.com/docs/agents-api/instances/create), [sizing](https://www.agent37.com/docs/agents-api/instance-sizing), [logs](https://www.agent37.com/docs/agents-api/logs), [upstream image source](https://github.com/agent37-platform/templates/tree/b2b-hermes/2026.11.12b/images/b2b/hermes).
