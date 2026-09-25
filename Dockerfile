# syntax=docker/dockerfile:1.7

# Build from the checked-out source; never depend on the retired MinIO image
# or on precompiled binaries from dl.min.io.
FROM golang:1.24.8-bookworm AS builder

WORKDIR /src
ENV CGO_ENABLED=0
ARG GOPROXY=https://proxy.golang.org

COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

COPY . .
ARG TARGETARCH
ARG SOURCE_REVISION=local
ARG SOURCE_DATE=
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    set -eu; \
    version="${SOURCE_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"; \
    release_date="$(printf '%s' "$version" | tr ':' '-')"; \
    short_revision="$(printf '%s' "$SOURCE_REVISION" | cut -c1-12)"; \
    GOOS=linux GOARCH="${TARGETARCH:-amd64}" \
      go build -buildvcs=false -tags kqueue -trimpath \
        -ldflags "-s -w \
          -X github.com/minio/minio/cmd.Version=${version} \
          -X github.com/minio/minio/cmd.ReleaseTag=DEVELOPMENT.${release_date} \
          -X github.com/minio/minio/cmd.CommitID=${SOURCE_REVISION} \
          -X github.com/minio/minio/cmd.ShortCommitID=${short_revision} \
          -X github.com/minio/minio/cmd.CopyrightYear=${version%%-*}" \
        -o /build/minio .; \
    /build/minio --version

FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

ARG SOURCE_REVISION=local
LABEL org.opencontainers.image.source="https://github.com/fengwk/minio" \
      org.opencontainers.image.licenses="AGPL-3.0-or-later" \
      org.opencontainers.image.revision="${SOURCE_REVISION}"

COPY --from=builder /build/minio /usr/local/bin/minio
COPY --chmod=755 dockerscripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY LICENSE NOTICE /usr/share/doc/minio/

EXPOSE 9000 9001
VOLUME ["/data"]
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["server", "/data"]
