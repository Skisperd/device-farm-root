#!/usr/bin/env bash
# Headless Android emulators (no window, no Dock icon) connected to the Device Farm hub.
#
# Docker on macOS has no KVM, so emulators run natively on the Mac in the background:
# the Docker hub sees them via host.docker.internal:<adb-port>.
# Devices come from the catalog at infra/emulators/devices.conf (order = priority).
#
# Usage:
#   scripts/emulators.sh up [N]      create/start the first N devices (default: EMULATORS from .env or 2)
#   scripts/emulators.sh down        stop project emulators
#   scripts/emulators.sh status      list running emulators
#   scripts/emulators.sh list        list the device catalog
#   scripts/emulators.sh reset       stop and delete project AVDs (recreated on next up)
#   scripts/emulators.sh view [i]    mirror emulator i screen (scrcpy), for debugging only
#
# EMULATOR_DEVICES=pixel_8,galaxy_a55 picks specific devices from the catalog.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
[[ -f "$ENV_FILE" ]] && set -a && source "$ENV_FILE" && set +a

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
ADB="${SDK}/platform-tools/adb"
EMULATOR="${SDK}/emulator/emulator"
SDKMANAGER="${SDK}/cmdline-tools/latest/bin/sdkmanager"
AVDMANAGER="${SDK}/cmdline-tools/latest/bin/avdmanager"

CATALOG="${EMULATOR_CATALOG:-${ROOT_DIR}/infra/emulators/devices.conf}"
ARCH="$([[ "$(uname -m)" == "arm64" ]] && echo arm64-v8a || echo x86_64)"
AVD_PREFIX="avdfarm"
PIN="${EMULATOR_PIN:-1234}"
BASE_PORT=5554
LOG_DIR="${ROOT_DIR}/.emulators"

log() { echo "[emulators] $*"; }

java_home() {
  [[ -n "${JAVA_HOME:-}" ]] && return 0
  if [[ -x /usr/libexec/java_home ]]; then
    JAVA_HOME="$(/usr/libexec/java_home -v 17 2>/dev/null || /usr/libexec/java_home)"
    export JAVA_HOME
  fi
}

# google_apis_playstore: production image, no built-in root
system_image() { echo "system-images;android-$1;google_apis_playstore;${ARCH}"; }

catalog() { grep -vE '^[[:space:]]*(#|$)' "$CATALOG"; }

selected_devices() {
  local count="$1"
  if [[ -n "${EMULATOR_DEVICES:-}" ]]; then
    local id
    for id in ${EMULATOR_DEVICES//,/ }; do
      catalog | awk -F'|' -v id="$id" '$1 == id' | grep . || { echo "device '${id}' not found in ${CATALOG}" >&2; exit 1; }
    done
  else
    catalog
  fi | head -n "$count"
}

avd_name() { echo "${AVD_PREFIX}_$1"; }
console_port() { echo $((BASE_PORT + ($1 - 1) * 2)); }
adb_port() { echo $(($(console_port "$1") + 1)); }

ensure_sdk() {
  local rows="$1" packages=() api
  if [[ ! -x "$SDKMANAGER" ]]; then
    echo "Android cmdline-tools not found at ${SDK}. See README > Setup." >&2
    exit 1
  fi
  java_home
  [[ -x "$EMULATOR" ]] || packages+=("emulator")
  [[ -x "$ADB" ]] || packages+=("platform-tools")
  for api in $(cut -d'|' -f3 <<< "$rows" | sort -u); do
    local image
    image="$(system_image "$api")"
    [[ -d "${SDK}/${image//;//}" ]] || packages+=("$image")
  done
  if [[ ${#packages[@]} -gt 0 ]]; then
    log "installing ${packages[*]} (one-time download, ~1.5 GB per image)"
    yes | "$SDKMANAGER" --licenses >/dev/null 2>&1 || true
    "$SDKMANAGER" --install "${packages[@]}" >/dev/null
  fi
}

get_config() {
  { grep -m1 -E "^$2[[:space:]]*=" "$1" 2>/dev/null || true; } | cut -d= -f2- | sed 's/^[[:space:]]*//'
}

set_config() {
  local config="$1" key="$2" value="$3"
  if grep -qE "^${key}[[:space:]]*=" "$config"; then
    sed -i '' -E "s|^${key}[[:space:]]*=.*|${key}=${value}|" "$config"
  else
    echo "${key}=${value}" >> "$config"
  fi
}

# Create AVD from catalog line: id|name|api|width|height|density|ram_mb
ensure_avd() {
  local id name api width height density ram avd
  IFS='|' read -r id name api width height density ram <<< "$1"
  avd="$(avd_name "$id")"
  "$EMULATOR" -list-avds | grep -qx "$avd" && return 0

  log "creating AVD ${avd} (${name}, Android API ${api}, ${width}x${height} @${density}dpi)"
  echo no | "$AVDMANAGER" create avd -n "$avd" -k "$(system_image "$api")" -d pixel_6 >/dev/null
  local config="$HOME/.android/avd/${avd}.avd/config.ini"
  set_config "$config" avd.ini.displayname "$name"
  set_config "$config" hw.device.manufacturer "${name%% *}"
  set_config "$config" hw.device.name "$id"
  set_config "$config" hw.lcd.width "$width"
  set_config "$config" hw.lcd.height "$height"
  set_config "$config" hw.lcd.density "$density"
  set_config "$config" hw.ramSize "${EMULATOR_RAM_MB:-$ram}"
  set_config "$config" hw.keyboard yes
  set_config "$config" skin.name "${width}x${height}"
  set_config "$config" skin.path _no_skin
}

running_avd_on() {
  { "$ADB" -s "emulator-$1" emu avd name </dev/null 2>/dev/null || true; } | head -1 | tr -d '\r'
}

wait_boot() {
  local serial="$1"
  "$ADB" -s "$serial" wait-for-device </dev/null
  for _ in $(seq 1 150); do
    [[ "$("$ADB" -s "$serial" shell getprop sys.boot_completed </dev/null 2>/dev/null | tr -d '\r')" == "1" ]] && return 0
    sleep 2
  done
  echo "timeout waiting for ${serial} to boot" >&2
  return 1
}

prepare_device() {
  local serial="$1"
  # Lock screen PIN (required by some apps). Fails silently if already set.
  "$ADB" -s "$serial" shell locksettings set-pin "$PIN" </dev/null >/dev/null 2>&1 || true
  "$ADB" -s "$serial" shell settings put global window_animation_scale 0 </dev/null
  "$ADB" -s "$serial" shell settings put global transition_animation_scale 0 </dev/null
  "$ADB" -s "$serial" shell settings put global animator_duration_scale 0 </dev/null
  "$ADB" -s "$serial" shell svc power stayon true </dev/null
  "$ADB" -s "$serial" shell input keyevent KEYCODE_WAKEUP </dev/null
  # Spoof ro.product.model so the farm shows the real device name instead of sdk_gphone64_arm64.
  # Requires Magisk root (rootAVD). Fails silently if root is not available.
  local avd_id model
  avd_id="$(running_avd_on "${serial#emulator-}" 2>/dev/null | sed "s/^${AVD_PREFIX}_//")"
  model="$(grep "^${avd_id}|" "$CATALOG" | cut -d'|' -f2)"
  if [[ -n "$model" ]]; then
    "$ADB" -s "$serial" shell "su -c \"resetprop ro.product.model '${model}'; resetprop ro.product.name '${model}'\"" </dev/null 2>/dev/null || true
  fi
}

sync_env() {
  local count="$1" targets=()
  for i in $(seq 1 "$count"); do targets+=("host.docker.internal:$(adb_port "$i")"); done
  local current others=()
  current="$(grep -E '^ADB_CONNECT_DEVICES=' "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- || true)"
  for d in ${current//,/ }; do [[ "$d" == host.docker.internal:* ]] || others+=("$d"); done
  local value line
  value="$(printf '%s\n' "${targets[@]}" "${others[@]+"${others[@]}"}" | awk 'NF' | paste -sd, -)"
  line="ADB_CONNECT_DEVICES=${value}"
  [[ -f "$ENV_FILE" ]] || cp "${ROOT_DIR}/.env.example" "$ENV_FILE"
  grep -qx "$line" "$ENV_FILE" && return 1
  if grep -q '^ADB_CONNECT_DEVICES=' "$ENV_FILE"; then
    sed -i '' "s|^ADB_CONNECT_DEVICES=.*|${line}|" "$ENV_FILE"
  else
    echo "$line" >> "$ENV_FILE"
  fi
  log ".env updated: ${line}"
  export ADB_CONNECT_DEVICES="$value"
  return 0
}

cmd_up() {
  local count="${1:-${EMULATORS:-2}}" rows
  rows="$(selected_devices "$count")"
  ensure_sdk "$rows"
  mkdir -p "$LOG_DIR"
  "$ADB" start-server >/dev/null

  local i=0 row
  while IFS= read -r row; do
    i=$((i + 1))
    local id avd port current
    id="${row%%|*}"
    avd="$(avd_name "$id")"
    port="$(console_port "$i")"
    ensure_avd "$row"
    current="$(running_avd_on "$port")"
    if [[ "$current" == "$avd" ]]; then
      log "${avd} already running (emulator-${port})"
      continue
    elif [[ -n "$current" ]]; then
      echo "port ${port} in use by AVD ${current}; run 'scripts/emulators.sh down' first" >&2
      exit 1
    fi
    log "starting ${avd} headless on port ${port}"
    nohup "$EMULATOR" -avd "$avd" -port "$port" \
      -no-window -no-audio -no-boot-anim -gpu swiftshader_indirect \
      </dev/null > "${LOG_DIR}/${avd}.log" 2>&1 &
  done <<< "$rows"

  local total="$i"
  for i in $(seq 1 "$total"); do
    local serial="emulator-$(console_port "$i")"
    wait_boot "$serial"
    prepare_device "$serial"
    log "$(running_avd_on "$(console_port "$i")") ready (${serial}, hub: host.docker.internal:$(adb_port "$i"))"
  done

  if sync_env "$total" && docker inspect appium-hub >/dev/null 2>&1; then
    log "recreating hub to apply new device list"
    docker compose -f "${ROOT_DIR}/infra/docker-compose.yml" --env-file "$ENV_FILE" up -d --force-recreate appium-hub >/dev/null
  fi
  log "check with: make farm-status"
}

project_emulators() {
  "$ADB" devices | awk '$1 ~ /^emulator-/ {print $1}' | while read -r serial; do
    local name
    name="$(running_avd_on "${serial#emulator-}")"
    [[ "$name" == "${AVD_PREFIX}_"* ]] && echo "${serial} ${name}"
  done
}

cmd_down() {
  local found=0
  while read -r serial name; do
    [[ -z "$serial" ]] && continue
    found=1
    log "stopping ${name} (${serial})"
    "$ADB" -s "$serial" emu kill </dev/null >/dev/null 2>&1 || true
  done < <(project_emulators)
  [[ "$found" == 0 ]] && log "no project emulators running"
  return 0
}

cmd_status() {
  local rows
  rows="$(project_emulators)"
  if [[ -z "$rows" ]]; then
    log "no project emulators running"
    return 0
  fi
  printf "%-16s %-24s %-11s %-8s %s\n" "SERIAL" "DEVICE" "SCREEN" "ANDROID" "HUB"
  while read -r serial name; do
    local version config display screen
    version="$("$ADB" -s "$serial" shell getprop ro.build.version.release </dev/null 2>/dev/null | tr -d '\r')"
    config="$HOME/.android/avd/${name}.avd/config.ini"
    display="$(get_config "$config" avd.ini.displayname)"
    screen="$(get_config "$config" hw.lcd.width)x$(get_config "$config" hw.lcd.height)"
    printf "%-16s %-24s %-11s %-8s host.docker.internal:%s\n" \
      "$serial" "${display:-$name}" "$screen" "$version" $((${serial#emulator-} + 1))
  done <<< "$rows"
}

cmd_list() {
  printf "%-4s %-15s %-24s %-8s %-11s %-6s %s\n" "#" "ID" "DEVICE" "ANDROID" "SCREEN" "DPI" "RAM"
  local n=0
  while IFS='|' read -r id name api width height density ram; do
    n=$((n + 1))
    printf "%-4s %-15s %-24s %-8s %-11s %-6s %s MB\n" "$n" "$id" "$name" "API ${api}" "${width}x${height}" "$density" "$ram"
  done < <(catalog)
}

cmd_reset() {
  cmd_down
  sleep 3
  java_home
  for avd in $("$EMULATOR" -list-avds | grep "^${AVD_PREFIX}_"); do
    log "deleting AVD ${avd}"
    "$AVDMANAGER" delete avd -n "$avd" >/dev/null
  done
}

cmd_view() {
  local serial="emulator-$(console_port "${1:-1}")"
  command -v scrcpy >/dev/null || { echo "install scrcpy: brew install scrcpy" >&2; exit 1; }
  ADB="$ADB" scrcpy -s "$serial" --window-title "$(running_avd_on "${serial#emulator-}")" >/dev/null 2>&1 &
  log "mirroring ${serial} (close window when done; emulator keeps running)"
}

case "${1:-}" in
  up)     cmd_up "${2:-}" ;;
  down)   cmd_down ;;
  status) cmd_status ;;
  list)   cmd_list ;;
  reset)  cmd_reset ;;
  view)   cmd_view "${2:-1}" ;;
  *) echo "usage: $0 up [N] | down | status | list | reset | view [i]" >&2; exit 1 ;;
esac
