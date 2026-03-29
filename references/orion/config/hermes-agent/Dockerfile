# =============================================================================
# Hermes Agent — Nous Research autonomous AI agent
# Build: docker build -t hermes-agent:local -f config/hermes-agent/Dockerfile .
# =============================================================================

FROM nikolaik/python-nodejs:python3.11-nodejs22

ARG HERMES_AGENT_VERSION=main

ENV HERMES_HOME=/data \
    PYTHONUNBUFFERED=1

# Install uv package manager
RUN pip install --no-cache-dir uv

# Clone and install hermes-agent with all extras
RUN git clone --depth 1 --branch ${HERMES_AGENT_VERSION} \
      https://github.com/NousResearch/hermes-agent.git /opt/hermes-agent && \
    cd /opt/hermes-agent && \
    uv pip install --system -e ".[all]"

# Create data directory
RUN mkdir -p /data/memories /data/sessions /data/skills /data/cron /data/logs /data/cache

WORKDIR /opt/hermes-agent

EXPOSE 8642 8644

HEALTHCHECK --interval=30s --timeout=10s --retries=5 --start-period=30s \
  CMD curl -sf http://localhost:8642/health || exit 1

CMD ["hermes", "gateway", "run"]
