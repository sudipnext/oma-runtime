# OMA runtime

A general-purpose Hermes image for Open Marketing Agency on Agent37. **WordPress, PHP, MariaDB and other application stacks are not bundled or started.** Each deployment installs only what its mission needs.

Source: [sudipnext/oma-runtime](https://github.com/sudipnext/oma-runtime). Public package: [GHCR](https://github.com/sudipnext/oma-runtime/pkgs/container/oma-runtime).

The image reuses Agent37's digest-pinned `hermes-base:2026.11.12b` (Hermes v0.23.1), including its gateway, Chromium/browser tools, terminal, file browser, Python/uv, Node.js/npm, git and native CLI tools. The base is Debian, and runs as `node` (UID 1000) with the upstream entrypoint unchanged. Ubuntu and a Docker daemon inside the instance are not required.

## Build and test

```bash
docker build --platform linux/amd64 -t oma-runtime:test .
bash smoke-test.sh oma-runtime:test
```

The regression check boots on an empty home under 4 GB / 2 CPU limits, verifies the gateway and general tools, and checks that a CMS/database was not installed. It writes a Hermes skill and a state marker, then recreates the container on the same volume with output pipes created as root before dropping to `node`, matching Agent37 VM startup. It checks persistence and removes only its own temporary container and volume. Real mission/browser concurrency needs separate workload testing.

Run locally with loopback-only bindings; the terminal and file services rely on Agent37's authenticated edge:

```bash
docker run -d --name oma-experiment --memory=4g --cpus=2 \
  --mount source=oma-experiment-home,target=/home/node \
  -p 127.0.0.1:3737:3737 oma-runtime:test
docker logs -f oma-experiment
```

## Optional software

An agent with explicitly allowed terminal tools can install Python packages with `uv`/`pip`, Node packages with `npm`, and system packages with `sudo apt-get`. WordPress can be installed when a user requests a website; it is one possible application, not a prerequisite for every deployment. OMA's future profile/tool policy must deliberately grant installation authority where appropriate. A model prompt alone does not grant tools or permissions.

Keep application code, content, configuration and databases under `/home/node`, the persistent volume. **An image update replaces system packages and files outside that directory.** Optional application setup therefore needs a repeatable installation recipe, or a dedicated application image once a deployment requires that stack. Do not rely on an agent's one-off package installation surviving an image update. Restarts keep the running image; updates reapply it.

Start optional services through a process supervisor or an explicit boot hook. Agent37 VM images do not boot a normal systemd installation. Bind application HTTP services to `0.0.0.0` on their own ports; the Hermes gateway keeps port `3737`. Obtain authenticated URLs through Agent37. If a deployment actually needs Docker Compose or nested containers, use a VM image with Docker installed and keep Docker's data root under the persistent home.

## Publish

GitHub Actions builds `linux/amd64`, runs the regression check, and only then publishes the same tested image. Main publishes `latest` and `sha-<full-commit>`; `v*` tags also publish a release tag. Pull requests test without publishing. The built-in `GITHUB_TOKEN` has `packages: write`; credentials never belong in the Dockerfile.

The GHCR package must be public for anonymous registry access. Use a commit tag or digest for Agent37 registration instead of `latest`. Earlier experimental revisions bundled WordPress; use the current general-purpose release for new deployments.

## Register and deploy

Run these from the administrator/control plane. Keep `AGENT37_API_KEY` there, never in an image or agent instance. Set `OMA_IMAGE` to the published commit tag or digest:

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

For an existing template, use `PATCH /v1/templates/oma-runtime` with a new image reference. Read back its revision; registering snapshots the image, so re-pushing a tag never updates an existing template or instance.

To create a real Linux VM, use the returned revision below (creation incurs Agent37 usage):

```bash
curl --fail-with-body https://api.agent37.com/v1/instances \
  -H "Authorization: Bearer $AGENT37_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"name":"OMA experiment","template":"oma-runtime@<revision>","type":"vm","resources":{"cpu":2,"memory":4,"disk":12},"auto_sleep":false}'
```

`type: vm` supplies its own Linux kernel; the cheaper `default` type is a sandbox. Both accept this image. Use `vm` when a workload requires a full kernel, such as a local database or Docker. VM and sandbox compute rates differ.

The base has no model credentials. Bootstrap a scoped LiteLLM/provider configuration in `~/.hermes/config.yaml`, install the chosen personas/profiles/skills on the persistent home, and verify a real model turn before starting a mission. For Agent37-managed inference, configure its instance-scoped endpoint/token from the environment and set a budget. Its managed token rotates after restart: refresh any literal credentials at every boot, or configure them again before the next test. Keep provider administration keys and LiteLLM master keys outside the instance.

## Control and observability

Use Agent37's exec API or SSH for commands and files, its lifecycle API for start/stop/restart/update, and signed URLs for the gateway (`3737`), dashboard (`9119`), terminal (`7681`) and file browser (`8080`). Do not publish administration ports as unauthenticated public endpoints.

`GET https://sandbox.agent37.app/v1/instances/<id>/logs?tail=200` with `X-Agent37-Key` returns boot/runtime logs even when an instance is stopped or failed. Inspect the instance's `status_reason` when nothing started. Future OMA dashboards should expose these through the existing FastAPI/Next.js control plane with owner-scoped deployment records and authorization. That dashboard and playbook provisioning are separate from this reusable base image.

References: [custom images](https://www.agent37.com/docs/agents-api/custom-image), [templates](https://www.agent37.com/docs/agents-api/templates), [VMs](https://www.agent37.com/docs/agents-api/vm-instances), [exec](https://www.agent37.com/docs/agents-api/exec), [image updates](https://www.agent37.com/docs/agents-api/instances/update), [logs](https://www.agent37.com/docs/agents-api/logs).
