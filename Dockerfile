ARG FOUNDRY_IMAGE=ghcr.io/foundry-rs/foundry:v1.7.1@sha256:8347b728d5d393dac1c018691b36f506d23b9dcd78341d40ea0fcb11c3a19cdd
FROM ${FOUNDRY_IMAGE} AS foundry

FROM node:24.10.0-bookworm-slim@sha256:b8d2197aff9129d16c801a3e3e1b2a873c4946480f5a310f38056df2268c38d9

ENV PNPM_HOME=/pnpm
ENV PATH=${PNPM_HOME}:${PATH}

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY --from=foundry /usr/local/bin/anvil /usr/local/bin/anvil
COPY --from=foundry /usr/local/bin/cast /usr/local/bin/cast
COPY --from=foundry /usr/local/bin/forge /usr/local/bin/forge

RUN corepack enable && corepack prepare pnpm@9.15.4 --activate

WORKDIR /app

COPY package.json pnpm-lock.yaml ./
COPY patches ./patches
RUN pnpm install --frozen-lockfile

COPY foundry.toml remappings.txt gemforge.config.cjs gemforge.deployments.json ./
COPY hooks ./hooks
COPY lib ./lib
COPY src ./src
COPY templates ./templates
COPY admin-ui ./admin-ui
COPY scripts ./scripts

RUN pnpm admin:contracts && chmod +x scripts/run-local-admin-container.sh

EXPOSE 5173 8545

HEALTHCHECK --interval=5s --timeout=3s --start-period=90s --retries=12 \
  CMD node -e "fetch('http://127.0.0.1:5173').then((response) => process.exit(response.ok ? 0 : 1)).catch(() => process.exit(1))"

CMD ["./scripts/run-local-admin-container.sh"]
