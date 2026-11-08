# Update both Dockerfiles together; verify new bases with mix test.release.
ARG BUILDER_IMAGE="elixir:1.20.5-alpine@sha256:a2f0fe1bfd8a2f9cc91d913f4a12e6430e27e618720f753a514e2fff3d35f5a7"
ARG RUNNER_IMAGE="alpine:3.24.4@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf"

FROM ${BUILDER_IMAGE} AS builder

# install build dependencies
RUN apk add --no-cache build-base git

# prepare build dir
WORKDIR /app/lib/exdock_client

# install hex + rebar
RUN mix local.hex --force && \
  mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY build /app/build
COPY LICENSE /app/
COPY scripts/collect_licenses.exs /app/scripts/collect_licenses.exs
COPY lib/exdock_client/mix.exs lib/exdock_client/mix.lock ./
COPY lib/exdock_client/exdock_protocol exdock_protocol
COPY lib/exdock_client_runtime/mix.exs /app/lib/exdock_client_runtime/mix.exs
COPY lib/exdock_client_runtime/lib /app/lib/exdock_client_runtime/lib
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY lib/exdock_client/config/config.exs lib/exdock_client/config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY lib/exdock_client/lib lib

# Compile the release
RUN mix compile

# Changes to config/runtime.exs don't require recompiling the code
COPY lib/exdock_client/config/runtime.exs config/

COPY lib/exdock_client/rel rel
RUN mix release && elixir /app/scripts/collect_licenses.exs /app/lib/exdock_client/deps /app/release-licenses

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE}

ARG IMAGE_VERSION=dev
ARG IMAGE_REVISION=unknown
ARG IMAGE_SOURCE=""
LABEL org.opencontainers.image.title="Exdock agent" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.source="${IMAGE_SOURCE}" \
      org.opencontainers.image.licenses="MIT"

# Install runtime dependencies and create the unprivileged release user.
RUN apk add --no-cache docker-cli libstdc++ ncurses-libs openssl su-exec && \
  addgroup -S nonroot && \
  adduser -S nonroot -G nonroot

WORKDIR "/app"

# set runner ENV
ENV MIX_ENV="prod"

# Copy the tested release and its project/dependency notices.
COPY --from=builder /app/LICENSE /app/
COPY --from=builder /app/release-licenses /app/licenses
COPY --from=builder --chown=nonroot:nonroot /app/lib/exdock_client/_build/${MIX_ENV}/rel/exdock_client ./
COPY --chmod=755 lib/exdock_client/docker-entrypoint.sh /app/bin/docker-entrypoint

ENTRYPOINT ["/app/bin/docker-entrypoint"]
CMD ["/app/bin/exdock_client", "start"]
