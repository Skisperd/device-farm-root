#!/usr/bin/env bash
# Starts the adb server, connects TCP devices and launches Appium with the device-farm plugin.
#
# ADB_CONNECT_DEVICES: comma-separated list of host:port entries (Mac emulators via
#                      host.docker.internal:5555..., Wi-Fi devices, Docker emulators).
# /host-adb/adbkey:    host adb key (mounted by compose). Devices already authorised on the
#                      host accept the hub without a new "Allow USB debugging?" prompt.
set -euo pipefail

log() { echo "[hub] $*"; }

if [[ -f /host-adb/adbkey ]]; then
  mkdir -p "$HOME/.android"
  cp /host-adb/adbkey "$HOME/.android/adbkey"
  [[ -f /host-adb/adbkey.pub ]] && cp /host-adb/adbkey.pub "$HOME/.android/adbkey.pub"
  chmod 600 "$HOME/.android/adbkey"
  log "using host adb key"
fi

adb start-server >/dev/null

device_state() {
  adb devices | awk -v d="$1" '$1 == d {print $2}'
}

declare -A LAST_STATE=()

connect_devices() {
  local targets="${ADB_CONNECT_DEVICES// /}"
  [[ -z "$targets" ]] && return 0
  IFS=',' read -ra devices <<< "$targets"
  for device in "${devices[@]}"; do
    local state
    state="$(device_state "$device")"
    if [[ "$state" != "device" ]]; then
      [[ -n "$state" ]] && adb disconnect "$device" >/dev/null 2>&1 || true
      adb connect "$device" >/dev/null 2>&1 || true
      sleep 1
      state="$(device_state "$device")"
    fi
    state="${state:-unavailable}"
    if [[ "${LAST_STATE[$device]:-}" != "$state" ]]; then
      log "${device}: ${state}"
      LAST_STATE[$device]="$state"
    fi
  done
}

connect_devices
log "devices visible to adb:"
adb devices -l | tail -n +2 | sed '/^$/d; s/^/[hub]   /'

(
  while true; do
    sleep "${ADB_RECONNECT_INTERVAL}"
    connect_devices
  done
) &

exec appium server \
  --port "${APPIUM_PORT}" \
  --config "${APPIUM_CONFIG}" \
  --use-plugins=device-farm \
  --allow-insecure=uiautomator2:adb_shell \
  ${APPIUM_EXTRA_ARGS:-}
