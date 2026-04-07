#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Hive"
BUNDLE_ID="com.hive.Hive"
BUILD_CONFIG="${BUILD_CONFIG:-release}"
INSTALL_DIR="${INSTALL_DIR:-/Applications/Utilities}"
APP_PATH="${INSTALL_DIR}/${APP_NAME}.app"
BIN_PATH="${ROOT_DIR}/.build/${BUILD_CONFIG}/${APP_NAME}"
PLIST_TEMPLATE="${ROOT_DIR}/Support/Hive-Info.plist"
LAUNCH_AGENT_LABEL="${BUNDLE_ID}"
TARGET_USER="${SUDO_USER:-$(id -un)}"
TARGET_UID="$(id -u "${TARGET_USER}")"
TARGET_HOME="$(dscl . -read "/Users/${TARGET_USER}" NFSHomeDirectory | awk '{print $2}')"
LAUNCH_AGENT_DIR="${TARGET_HOME}/Library/LaunchAgents"
LAUNCH_AGENT_PATH="${LAUNCH_AGENT_DIR}/${LAUNCH_AGENT_LABEL}.plist"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hive-install.XXXXXX")"
STAGED_APP_PATH="${TMP_DIR}/${APP_NAME}.app"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

stop_running_hives() {
  /usr/bin/osascript -e 'tell application id "com.hive.Hive" to quit' >/dev/null 2>&1 || true
  pkill -x "${APP_NAME}" >/dev/null 2>&1 || true

  for _ in {1..20}; do
    if ! pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
  done

  pkill -9 -x "${APP_NAME}" >/dev/null 2>&1 || true
}

echo "Building ${APP_NAME} (${BUILD_CONFIG})..."
swift build -c "${BUILD_CONFIG}" --package-path "${ROOT_DIR}"

if [[ ! -x "${BIN_PATH}" ]]; then
  echo "error: expected built binary at ${BIN_PATH}" >&2
  exit 1
fi

mkdir -p "${STAGED_APP_PATH}/Contents/MacOS"
install -m 755 "${BIN_PATH}" "${STAGED_APP_PATH}/Contents/MacOS/${APP_NAME}"
install -m 644 "${PLIST_TEMPLATE}" "${STAGED_APP_PATH}/Contents/Info.plist"

plutil -lint "${STAGED_APP_PATH}/Contents/Info.plist" >/dev/null

mkdir -p "${INSTALL_DIR}"
if [[ ! -w "${INSTALL_DIR}" ]]; then
  echo "error: cannot write to ${INSTALL_DIR}" >&2
  echo "hint: re-run with sudo or set INSTALL_DIR to a writable location" >&2
  exit 1
fi

launchctl bootout "gui/${TARGET_UID}/${LAUNCH_AGENT_LABEL}" >/dev/null 2>&1 || true
stop_running_hives
rm -rf "${APP_PATH}"
ditto "${STAGED_APP_PATH}" "${APP_PATH}"

mkdir -p "${LAUNCH_AGENT_DIR}"
cat >"${LAUNCH_AGENT_PATH}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LAUNCH_AGENT_LABEL}</string>
  <key>LimitLoadToSessionType</key>
  <array>
    <string>Aqua</string>
  </array>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>${APP_PATH}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
EOF

plutil -lint "${LAUNCH_AGENT_PATH}" >/dev/null
if [[ -n "${SUDO_USER:-}" ]]; then
  chown "${TARGET_USER}" "${LAUNCH_AGENT_PATH}"
fi
launchctl bootstrap "gui/${TARGET_UID}" "${LAUNCH_AGENT_PATH}"
launchctl kickstart -k "gui/${TARGET_UID}/${LAUNCH_AGENT_LABEL}" >/dev/null 2>&1 || true

echo "Installed ${APP_PATH}"
echo "LaunchAgent loaded: ${LAUNCH_AGENT_PATH}"
