ARG ENV_GARAGE_VERSION
FROM dxflrs/garage:${ENV_GARAGE_VERSION} AS garage

FROM alpine:3.20
COPY --from=garage /garage /garage
