# Update both Dockerfiles together; verify new bases with mix test.release.
ARG BUILDER_IMAGE="elixir:1.20.5-alpine@sha256:a2f0fe1bfd8a2f9cc91d913f4a12e6430e27e618720f753a514e2fff3d35f5a7"
ARG RUNNER_IMAGE="alpine:3.24.4@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf"

FROM ${BUILDER_IMAGE} AS builder

# install build dependencies
RUN apk add --no-cache build-base git rust cargo

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
  mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
COPY build build
COPY LICENSE ./
COPY scripts/collect_licenses.exs scripts/collect_licenses.exs
COPY lib/exdock_client/exdock_protocol lib/exdock_client/exdock_protocol
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# download tailwind and esbuild if they're missing
RUN mix assets.setup

COPY priv priv
COPY lib/exdock lib/exdock
COPY lib/exdock.ex lib/exdock.ex
COPY lib/exdock_web lib/exdock_web
COPY lib/exdock_web.ex lib/exdock_web.ex
COPY assets assets

# compile assets
RUN mix assets.deploy

# Compile the release
RUN mix compile

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release && elixir /app/scripts/collect_licenses.exs /app/deps /app/release-licenses

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE}

ARG IMAGE_VERSION=dev
ARG IMAGE_REVISION=unknown
ARG IMAGE_SOURCE=""
LABEL org.opencontainers.image.title="Exdock server" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.source="${IMAGE_SOURCE}" \
      org.opencontainers.image.licenses="MIT"

# Install runtime dependencies and create the unprivileged release user.
RUN apk add --no-cache ca-certificates libstdc++ lksctp-tools ncurses-libs openssl && \
  addgroup -S nonroot && \
  adduser -S nonroot -G nonroot

WORKDIR "/app"

# set runner ENV
ENV MIX_ENV="prod"
ENV PHX_SERVER="true"
ENV DATABASE_PATH="/data/db/exdock.db"

# Copy the tested release and its project/dependency notices.
COPY --from=builder /app/LICENSE /app/
COPY --from=builder /app/release-licenses /app/licenses
COPY --from=builder --chown=nonroot:nonroot /app/_build/${MIX_ENV}/rel/exdock ./
RUN chmod +x /app/bin/server /app/bin/migrate && \
  mkdir -p /data/db && \
  chown -R nonroot:nonroot /data/db

USER nonroot

CMD ["/app/bin/exdock", "start"]
