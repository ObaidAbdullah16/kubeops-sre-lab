# syntax=docker/dockerfile:1
# Cross-compiles on the build machine, so a multi-arch (amd64 + arm64) build needs no emulation.
FROM --platform=$BUILDPLATFORM golang:1.27-alpine AS build
ARG TARGETOS=linux
ARG TARGETARCH
ARG VERSION=dev
WORKDIR /src
COPY . .
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o /out/demo ./cmd/demo

FROM gcr.io/distroless/static-debian12:nonroot
LABEL org.opencontainers.image.source="https://github.com/ObaidAbdullah16/kubeops-sre-lab" \
      org.opencontainers.image.description="KubeOps SRE lab demo service (orders API + load generator)" \
      org.opencontainers.image.licenses="MIT"
COPY --from=build /out/demo /demo
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/demo"]
CMD ["serve"]
