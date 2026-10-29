*** Settings ***
Documentation    Smoke tests — verify the device farm is reachable and a session can be opened.
...
...              Run:
...                make robot-test SUITE=example/android_smoke.robot
...              or:
...                robot -v APP_PACKAGE:com.example.app \
...                      -v APP_ACTIVITY:.MainActivity \
...                      robot/tests/example/android_smoke.robot

Resource         ../../resources/AppiumMobile.resource

Suite Setup      Open Android Session
Suite Teardown   Close Android Session

# Tag all tests so you can run only "smoke" or exclude "slow"
Test Tags        smoke    android


*** Variables ***
# Override at runtime: -v APP_PACKAGE:com.example.app -v APP_ACTIVITY:.MainActivity
${APP_PACKAGE}      com.example.app
${APP_ACTIVITY}     .MainActivity


*** Test Cases ***

Farm Responds And Session Opens
    [Documentation]    Verify we can reach the hub and the session was created.
    [Tags]    connectivity
    ${source}=    Get Source
    Should Not Be Empty    ${source}
    Log    Page source length: ${source.__len__()}

App Is In Foreground
    [Documentation]    Verify the correct app is in the foreground after session open.
    [Tags]    app
    ${app}=    Get Foreground App
    Log    Foreground: ${app}[package] / ${app}[activity]
    Should Be Equal    ${app}[package]    ${APP_PACKAGE}

Navigate Back And Return Home
    [Documentation]    Press BACK then HOME — basic navigation sanity check.
    [Tags]    navigation
    Press Back
    Sleep    1s
    Press Home
    Sleep    1s
    Launch App By Package    ${APP_PACKAGE}    ${APP_ACTIVITY}
    Sleep    2s

Screenshot Is Captured
    [Documentation]    Take a named screenshot — confirms screen capture works.
    [Tags]    screenshot
    ${path}=    Take Named Screenshot    smoke_test
    File Should Exist    ${path}
