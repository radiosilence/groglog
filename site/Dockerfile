# syntax=docker/dockerfile:1.2
FROM ghcr.io/radiosilence/nano-web:latest

LABEL org.opencontainers.image.source="https://github.com/radiosilence/groglog" \
  org.opencontainers.image.url="https://groglog.io" \
  org.opencontainers.image.title="groglog-site" \
  org.opencontainers.image.description="groglog.io" \
  org.opencontainers.image.vendor="GrogLog"

COPY public /public
ENV PORT=3000
EXPOSE 3000
