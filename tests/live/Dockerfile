# Faixa B isolation image — a throwaway Linux box with the claude CLI + the loop's runtime deps.
# The real repo is mounted READ-ONLY at run time, so a headless model can never touch it; /work is
# an ephemeral in-container scratch. See run-in-docker.sh.
FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      git jq python3 python3-pytest ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code

RUN useradd -m runner && mkdir -p /work && chown runner /work
USER runner
ENV HOME=/home/runner
WORKDIR /work
CMD ["bash"]
