# Appium Hub + Device Farm
# Base image includes Android SDK, adb, Node, Appium 3 and UiAutomator2 driver.
# linux/amd64 only: on Apple Silicon Mac it runs via Rosetta in Docker Desktop.
ARG APPIUM_IMAGE=appium/appium:v3.7.0-p1
FROM --platform=linux/amd64 ${APPIUM_IMAGE}

ARG DEVICE_FARM_VERSION=12.0.2

USER root
RUN apt-get -qqy update \
    && apt-get -qqy --no-install-recommends install curl ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

COPY --chmod=755 entrypoint.sh /usr/local/bin/appium-hub-entrypoint
COPY hub.config.json /etc/appium/hub.config.json

USER ${USERID}:${GROUPID}
RUN appium plugin install --source=npm appium-device-farm@${DEVICE_FARM_VERSION}

ENV APPIUM_PORT=4723 \
    APPIUM_CONFIG=/etc/appium/hub.config.json \
    ADB_CONNECT_DEVICES="" \
    ADB_RECONNECT_INTERVAL=15

EXPOSE 4723

HEALTHCHECK --interval=15s --timeout=5s --start-period=40s --retries=5 \
    CMD curl -fsS "http://localhost:${APPIUM_PORT}/status" || exit 1

ENTRYPOINT ["/usr/local/bin/appium-hub-entrypoint"]
