FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY analysis_options.yaml ./
COPY bin ./bin
COPY lib ./lib
COPY web ./web

RUN flutter build web --release
RUN dart build cli bin/chargeledger_server.dart

FROM debian:bookworm-slim AS runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=build /app/build/cli/linux_x64/bundle/bin/chargeledger_server /app/chargeledger_server
COPY --from=build /app/build/cli/linux_x64/bundle/lib /app/lib
COPY --from=build /app/build/web /app/web

ENV CHARGELEDGER_CONFIG=/app/info.yaml
ENV CHARGELEDGER_WEB_ROOT=/app/web
ENV PORT=8912

EXPOSE 8912

CMD ["/app/chargeledger_server"]
