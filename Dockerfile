# syntax=docker/dockerfile:1
# Debian-based Hermes, gateway, browser, Python/uv, Node.js and native CLI tools.
# Preserve Agent37's entrypoint and non-root user; applications are optional.
FROM ghcr.io/agent37-platform/hermes-base:2026.11.12b@sha256:ecfb43565f7edb3b827b662a9b896d76171730ea5c23b646f9038d73c1832f31

LABEL org.opencontainers.image.title="OMA runtime" \
      org.opencontainers.image.description="General-purpose Hermes runtime for Agent37; applications installed on demand" \
      org.opencontainers.image.source="https://github.com/sudipnext/oma-runtime"

COPY --chmod=0755 healthcheck.sh /usr/local/bin/oma-healthcheck
HEALTHCHECK --interval=15s --timeout=10s --start-period=120s --retries=4 CMD ["/usr/local/bin/oma-healthcheck"]
