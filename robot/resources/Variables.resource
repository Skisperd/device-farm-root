*** Settings ***
Documentation    Common variables for the Appium Device Farm test suites.
...              Override at runtime:  robot -v APPIUM_URL:http://... -v APP_PATH:/tmp/app.apk


*** Variables ***
# ── Hub connection ──────────────────────────────────────────────────────────────
${APPIUM_URL}         http://localhost:4723
${APPIUM_TIMEOUT}     30s

# ── Default Android capabilities ───────────────────────────────────────────────
${PLATFORM_NAME}      Android
${AUTOMATION_NAME}    UiAutomator2
${NEW_COMMAND_TIMEOUT}    120

# ── App under test — override via -v at runtime ────────────────────────────────
${APP_PATH}           ${EMPTY}
${APP_PACKAGE}        ${EMPTY}
${APP_ACTIVITY}       ${EMPTY}

# ── Output paths ────────────────────────────────────────────────────────────────
${RESULTS_DIR}        robot/results
${SCREENSHOTS_DIR}    robot/results/screenshots
