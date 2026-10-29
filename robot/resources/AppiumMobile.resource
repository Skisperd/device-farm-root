*** Settings ***
Documentation    Reusable keywords for Android automation via the Appium Device Farm.
...
...              Requires AppiumLibrary (robotframework-appiumlibrary).
...              The hub URL and capabilities are injected via Variables.resource.
...
...              Typical usage in a test suite:
...              | Resource    ../../resources/AppiumMobile.resource
...              | Suite Setup      Open Android Session
...              | Suite Teardown   Close Android Session

Library          AppiumLibrary    run_on_failure=Capture Page Screenshot
Resource         Variables.resource


*** Keywords ***

# ── Session management ─────────────────────────────────────────────────────────

Open Android Session
    [Documentation]    Open an Appium session against the device farm hub.
    ...                Builds capabilities from Variables.resource; override individual
    ...                variables via -v at the command line.
    ...
    ...                Pass appium:app to launch an APK, or appium:appPackage +
    ...                appium:appActivity to launch an already-installed app.
    [Arguments]    ${extra_caps}=&{EMPTY}

    &{caps}=    Create Dictionary
    ...    platformName=${PLATFORM_NAME}
    ...    appium:automationName=${AUTOMATION_NAME}
    ...    appium:newCommandTimeout=${NEW_COMMAND_TIMEOUT}
    ...    appium:noReset=False
    ...    appium:fullReset=False

    Run Keyword If    '${APP_PATH}' != '${EMPTY}'
    ...    Set To Dictionary    ${caps}    appium:app    ${APP_PATH}
    Run Keyword If    '${APP_PACKAGE}' != '${EMPTY}'
    ...    Set To Dictionary    ${caps}    appium:appPackage    ${APP_PACKAGE}
    Run Keyword If    '${APP_ACTIVITY}' != '${EMPTY}'
    ...    Set To Dictionary    ${caps}    appium:appActivity    ${APP_ACTIVITY}

    # Merge any caller-supplied extra capabilities
    FOR    ${key}    ${value}    IN    &{extra_caps}
        Set To Dictionary    ${caps}    ${key}    ${value}
    END

    Open Application    ${APPIUM_URL}    &{caps}
    Log    Session opened against ${APPIUM_URL}

Close Android Session
    [Documentation]    Capture a final screenshot then close the session.
    Run Keyword And Ignore Error    Capture Page Screenshot
    Close Application

# ── Waits ──────────────────────────────────────────────────────────────────────

Wait For Element
    [Documentation]    Wait up to ${timeout} for an element to appear.
    [Arguments]    ${locator}    ${timeout}=${APPIUM_TIMEOUT}
    Wait Until Element Is Visible    ${locator}    timeout=${timeout}

Wait For Element And Click
    [Documentation]    Wait for element, then tap it.
    [Arguments]    ${locator}    ${timeout}=${APPIUM_TIMEOUT}
    Wait For Element    ${locator}    ${timeout}
    Click Element    ${locator}

Wait For Element And Type
    [Documentation]    Wait for element, clear it, then type text.
    [Arguments]    ${locator}    ${text}    ${timeout}=${APPIUM_TIMEOUT}
    Wait For Element    ${locator}    ${timeout}
    Clear Text    ${locator}
    Input Text    ${locator}    ${text}

# ── Navigation ────────────────────────────────────────────────────────────────

Press Back
    Press Keycode    4

Press Home
    Press Keycode    3

Press Enter
    Press Keycode    66

Swipe Up
    [Documentation]    Swipe upward (scroll down in the view).
    [Arguments]    ${x}=540    ${start_y}=1400    ${end_y}=600    ${duration}=800
    Swipe    ${x}    ${start_y}    ${x}    ${end_y}    ${duration}

Swipe Down
    [Documentation]    Swipe downward (scroll up in the view).
    [Arguments]    ${x}=540    ${start_y}=600    ${end_y}=1400    ${duration}=800
    Swipe    ${x}    ${start_y}    ${x}    ${end_y}    ${duration}

# ── App management ────────────────────────────────────────────────────────────

Launch App By Package
    [Documentation]    Start an app that is already installed on the device.
    [Arguments]    ${package}    ${activity}
    Start Activity    ${package}    ${activity}

Get Foreground App
    [Documentation]    Return a dict with {package, activity} of the current foreground app.
    ${package}=    Get Current Package
    ${activity}=    Get Current Activity
    &{result}=    Create Dictionary    package=${package}    activity=${activity}
    RETURN    ${result}

# ── Assertions ────────────────────────────────────────────────────────────────

Element Should Contain Text
    [Documentation]    Assert element text contains the given substring.
    [Arguments]    ${locator}    ${expected}
    ${actual}=    Get Text    ${locator}
    Should Contain    ${actual}    ${expected}
    ...    msg=Element '${locator}' text '${actual}' does not contain '${expected}'

# ── Screenshots ───────────────────────────────────────────────────────────────

Take Named Screenshot
    [Documentation]    Save a screenshot with a specific filename under ${SCREENSHOTS_DIR}.
    [Arguments]    ${name}
    ${path}=    Set Variable    ${SCREENSHOTS_DIR}/${name}.png
    Capture Page Screenshot    ${path}
    Log    Screenshot saved: ${path}
    RETURN    ${path}
