#!/usr/bin/env python3
"""
Appium Device Farm MCP Server

Exposes the Appium hub and device farm as MCP tools for use with Claude Code
and Robot Framework test execution.

Run:
  python -m mcp.server          # via module (set PYTHONPATH=. first)
  python mcp/server.py          # direct

Environment variables:
  APPIUM_URL           Appium hub base URL (default: http://localhost:4723)
  ROBOT_TESTS_DIR      Root dir for Robot Framework tests (default: ./robot/tests)
  ROBOT_RESOURCES_DIR  Root dir for RF resources (default: ./robot/resources)
"""
from __future__ import annotations

import asyncio
import base64
import json
import os
import subprocess
import sys
import textwrap
from pathlib import Path
from typing import Any

import httpx
from mcp.server import Server
from mcp.server.stdio import stdio_server
import mcp.types as types

# ── configuration ──────────────────────────────────────────────────────────────
APPIUM_URL = os.getenv("APPIUM_URL", "http://localhost:4723").rstrip("/")
ROBOT_TESTS_DIR = Path(os.getenv("ROBOT_TESTS_DIR", "robot/tests"))
ROBOT_RESOURCES_DIR = Path(os.getenv("ROBOT_RESOURCES_DIR", "robot/resources"))

server = Server("appium-device-farm")

# ── helpers ────────────────────────────────────────────────────────────────────

def _client() -> httpx.AsyncClient:
    return httpx.AsyncClient(base_url=APPIUM_URL, timeout=30)


def _ok(data: Any) -> list[types.TextContent]:
    return [types.TextContent(type="text", text=json.dumps(data, indent=2, ensure_ascii=False))]


def _err(msg: str) -> list[types.TextContent]:
    return [types.TextContent(type="text", text=f"ERROR: {msg}")]


async def _get(path: str) -> Any:
    async with _client() as c:
        r = await c.get(path)
        r.raise_for_status()
        return r.json()


async def _post(path: str, body: dict) -> Any:
    async with _client() as c:
        r = await c.post(path, json=body)
        r.raise_for_status()
        return r.json()


async def _delete(path: str) -> Any:
    async with _client() as c:
        r = await c.delete(path)
        r.raise_for_status()
        return r.json()


# ── tool registry ──────────────────────────────────────────────────────────────

@server.list_tools()
async def list_tools() -> list[types.Tool]:
    return [
        types.Tool(
            name="farm_status",
            description=(
                "List all devices registered in the Appium Device Farm with their current "
                "status (free / busy / offline) and metadata (platform, version, UDID)."
            ),
            inputSchema={"type": "object", "properties": {}, "required": []},
        ),
        types.Tool(
            name="get_sessions",
            description="List all active Appium sessions on the hub.",
            inputSchema={"type": "object", "properties": {}, "required": []},
        ),
        types.Tool(
            name="create_session",
            description=(
                "Start a new Appium session. Returns the sessionId needed for subsequent commands.\n"
                "Required capabilities: platformName='Android', appium:app OR appium:appPackage + "
                "appium:appActivity.\n"
                "The device-farm plugin selects a free device automatically unless you pass "
                "appium:udid."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "capabilities": {
                        "type": "object",
                        "description": (
                            "W3C capabilities object. Example:\n"
                            '{"alwaysMatch": {"platformName": "Android", '
                            '"appium:app": "/tmp/myapp.apk", '
                            '"appium:automationName": "UiAutomator2"}}'
                        ),
                    }
                },
                "required": ["capabilities"],
            },
        ),
        types.Tool(
            name="delete_session",
            description="End an active Appium session and release the device.",
            inputSchema={
                "type": "object",
                "properties": {
                    "session_id": {"type": "string", "description": "Session ID to terminate"}
                },
                "required": ["session_id"],
            },
        ),
        types.Tool(
            name="get_page_source",
            description="Get the XML page source (UI hierarchy) of the current screen.",
            inputSchema={
                "type": "object",
                "properties": {
                    "session_id": {"type": "string"}
                },
                "required": ["session_id"],
            },
        ),
        types.Tool(
            name="take_screenshot",
            description="Capture a screenshot of the current screen. Returns base64-encoded PNG.",
            inputSchema={
                "type": "object",
                "properties": {
                    "session_id": {"type": "string"}
                },
                "required": ["session_id"],
            },
        ),
        types.Tool(
            name="find_element",
            description=(
                "Find an element on screen. Returns elementId for use in click/input commands.\n"
                "Strategy options: id, accessibility id, xpath, class name, -android uiautomator."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "session_id": {"type": "string"},
                    "strategy": {
                        "type": "string",
                        "enum": ["id", "accessibility id", "xpath", "class name", "-android uiautomator"],
                    },
                    "selector": {"type": "string", "description": "Locator value"},
                },
                "required": ["session_id", "strategy", "selector"],
            },
        ),
        types.Tool(
            name="click_element",
            description="Tap / click an element found by find_element.",
            inputSchema={
                "type": "object",
                "properties": {
                    "session_id": {"type": "string"},
                    "element_id": {"type": "string"},
                },
                "required": ["session_id", "element_id"],
            },
        ),
        types.Tool(
            name="input_text",
            description="Type text into an element (e.g. a text field).",
            inputSchema={
                "type": "object",
                "properties": {
                    "session_id": {"type": "string"},
                    "element_id": {"type": "string"},
                    "text": {"type": "string"},
                },
                "required": ["session_id", "element_id", "text"],
            },
        ),
        types.Tool(
            name="get_element_text",
            description="Get the visible text / content-desc of an element.",
            inputSchema={
                "type": "object",
                "properties": {
                    "session_id": {"type": "string"},
                    "element_id": {"type": "string"},
                },
                "required": ["session_id", "element_id"],
            },
        ),
        types.Tool(
            name="press_key",
            description=(
                "Send an Android KeyEvent to the device. Common keycodes:\n"
                "3=HOME, 4=BACK, 24=VOLUME_UP, 25=VOLUME_DOWN, 26=POWER, 66=ENTER, 82=MENU."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "session_id": {"type": "string"},
                    "keycode": {"type": "integer", "description": "Android KeyEvent keycode"},
                },
                "required": ["session_id", "keycode"],
            },
        ),
        types.Tool(
            name="swipe",
            description="Perform a swipe gesture from (startX, startY) to (endX, endY).",
            inputSchema={
                "type": "object",
                "properties": {
                    "session_id": {"type": "string"},
                    "start_x": {"type": "integer"},
                    "start_y": {"type": "integer"},
                    "end_x": {"type": "integer"},
                    "end_y": {"type": "integer"},
                    "duration_ms": {
                        "type": "integer",
                        "description": "Duration in milliseconds (default: 800)",
                        "default": 800,
                    },
                },
                "required": ["session_id", "start_x", "start_y", "end_x", "end_y"],
            },
        ),
        types.Tool(
            name="install_app",
            description=(
                "Install an APK on the device bound to the session. "
                "The path must be accessible from inside the Appium hub container or "
                "reachable via a URL."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "session_id": {"type": "string"},
                    "app_path": {
                        "type": "string",
                        "description": "Absolute path or URL to the APK",
                    },
                },
                "required": ["session_id", "app_path"],
            },
        ),
        types.Tool(
            name="get_current_activity",
            description="Return the currently-foreground package and activity.",
            inputSchema={
                "type": "object",
                "properties": {
                    "session_id": {"type": "string"}
                },
                "required": ["session_id"],
            },
        ),
        types.Tool(
            name="execute_script",
            description=(
                "Run a mobile: command or arbitrary JavaScript via executeScript. "
                "E.g. script='mobile: scroll', args=[{direction:'down'}]."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "session_id": {"type": "string"},
                    "script": {"type": "string"},
                    "args": {
                        "type": "array",
                        "description": "Arguments passed to the script",
                        "default": [],
                    },
                },
                "required": ["session_id", "script"],
            },
        ),
        types.Tool(
            name="run_robot_tests",
            description=(
                "Execute a Robot Framework test suite via `robot` CLI and return the output.\n"
                "suite_path is relative to the robot/tests directory (or absolute).\n"
                "variables is a dict of -v VAR:value pairs injected at runtime."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "suite_path": {
                        "type": "string",
                        "description": "Path to .robot file or directory (relative to robot/tests/)",
                    },
                    "variables": {
                        "type": "object",
                        "description": "Key-value pairs injected as -v NAME:VALUE",
                        "default": {},
                    },
                    "output_dir": {
                        "type": "string",
                        "description": "Output directory for reports (default: robot/results)",
                        "default": "robot/results",
                    },
                    "include_tags": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Only run tests with these tags (-i)",
                        "default": [],
                    },
                    "exclude_tags": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Skip tests with these tags (-e)",
                        "default": [],
                    },
                },
                "required": ["suite_path"],
            },
        ),
        types.Tool(
            name="list_robot_tests",
            description=(
                "List .robot files available under the robot/tests directory "
                "and their test case names (using `robot --dryrun`)."
            ),
            inputSchema={"type": "object", "properties": {}, "required": []},
        ),
    ]


# ── tool handlers ──────────────────────────────────────────────────────────────

@server.call_tool()
async def call_tool(name: str, arguments: dict) -> list[types.TextContent | types.ImageContent]:
    try:
        match name:
            case "farm_status":
                return await _farm_status()
            case "get_sessions":
                return await _get_sessions()
            case "create_session":
                return await _create_session(arguments["capabilities"])
            case "delete_session":
                return await _delete_session(arguments["session_id"])
            case "get_page_source":
                return await _get_page_source(arguments["session_id"])
            case "take_screenshot":
                return await _take_screenshot(arguments["session_id"])
            case "find_element":
                return await _find_element(
                    arguments["session_id"], arguments["strategy"], arguments["selector"]
                )
            case "click_element":
                return await _click_element(arguments["session_id"], arguments["element_id"])
            case "input_text":
                return await _input_text(
                    arguments["session_id"], arguments["element_id"], arguments["text"]
                )
            case "get_element_text":
                return await _get_element_text(arguments["session_id"], arguments["element_id"])
            case "press_key":
                return await _press_key(arguments["session_id"], arguments["keycode"])
            case "swipe":
                return await _swipe(
                    arguments["session_id"],
                    arguments["start_x"],
                    arguments["start_y"],
                    arguments["end_x"],
                    arguments["end_y"],
                    arguments.get("duration_ms", 800),
                )
            case "install_app":
                return await _install_app(arguments["session_id"], arguments["app_path"])
            case "get_current_activity":
                return await _get_current_activity(arguments["session_id"])
            case "execute_script":
                return await _execute_script(
                    arguments["session_id"],
                    arguments["script"],
                    arguments.get("args", []),
                )
            case "run_robot_tests":
                return await _run_robot_tests(
                    arguments["suite_path"],
                    arguments.get("variables", {}),
                    arguments.get("output_dir", "robot/results"),
                    arguments.get("include_tags", []),
                    arguments.get("exclude_tags", []),
                )
            case "list_robot_tests":
                return await _list_robot_tests()
            case _:
                return _err(f"Unknown tool: {name}")
    except httpx.HTTPStatusError as e:
        body = e.response.text[:500]
        return _err(f"HTTP {e.response.status_code}: {body}")
    except httpx.ConnectError:
        return _err(f"Cannot reach Appium hub at {APPIUM_URL}. Is the hub running?")
    except Exception as e:  # noqa: BLE001
        return _err(str(e))


# ── farm ───────────────────────────────────────────────────────────────────────

async def _farm_status() -> list[types.TextContent]:
    try:
        data = await _get("/device-farm/api/device")
    except httpx.HTTPStatusError:
        data = await _get("/status")
        return _ok({"hub": data})

    summary = []
    for d in data:
        status = "offline" if d.get("offline") else ("busy" if d.get("busy") else "free")
        summary.append({
            "udid": d.get("udid", ""),
            "name": d.get("name", ""),
            "platform": d.get("platform", ""),
            "version": d.get("sdk") or d.get("platformVersion", ""),
            "status": status,
            "host": d.get("host", ""),
        })
    return _ok({"devices": summary, "total": len(summary)})


async def _get_sessions() -> list[types.TextContent]:
    data = await _get("/sessions")
    sessions = data.get("value", [])
    result = [
        {
            "id": s.get("id"),
            "capabilities": s.get("capabilities", {}),
        }
        for s in sessions
    ]
    return _ok({"sessions": result, "count": len(result)})


# ── session lifecycle ──────────────────────────────────────────────────────────

async def _create_session(capabilities: dict) -> list[types.TextContent]:
    # Accept both W3C format and flat caps
    if "alwaysMatch" not in capabilities and "firstMatch" not in capabilities:
        capabilities = {"alwaysMatch": capabilities}
    body = {"capabilities": capabilities}
    data = await _post("/session", body)
    value = data.get("value", {})
    return _ok({
        "sessionId": data.get("sessionId") or value.get("sessionId"),
        "capabilities": value.get("capabilities", {}),
    })


async def _delete_session(session_id: str) -> list[types.TextContent]:
    await _delete(f"/session/{session_id}")
    return _ok({"deleted": session_id})


# ── screen ────────────────────────────────────────────────────────────────────

async def _get_page_source(session_id: str) -> list[types.TextContent]:
    data = await _get(f"/session/{session_id}/source")
    return [types.TextContent(type="text", text=data.get("value", ""))]


async def _take_screenshot(session_id: str) -> list[types.TextContent | types.ImageContent]:
    data = await _get(f"/session/{session_id}/screenshot")
    b64 = data.get("value", "")
    return [types.ImageContent(type="image", data=b64, mimeType="image/png")]


# ── elements ──────────────────────────────────────────────────────────────────

async def _find_element(session_id: str, strategy: str, selector: str) -> list[types.TextContent]:
    body = {"using": strategy, "value": selector}
    data = await _post(f"/session/{session_id}/element", body)
    value = data.get("value", {})
    elem_id = value.get("ELEMENT") or value.get("element-6066-11e4-a52e-4f735466cecf", "")
    return _ok({"elementId": elem_id, "strategy": strategy, "selector": selector})


async def _click_element(session_id: str, element_id: str) -> list[types.TextContent]:
    await _post(f"/session/{session_id}/element/{element_id}/click", {})
    return _ok({"clicked": element_id})


async def _input_text(session_id: str, element_id: str, text: str) -> list[types.TextContent]:
    body = {"text": text, "value": list(text)}
    await _post(f"/session/{session_id}/element/{element_id}/value", body)
    return _ok({"typed": text, "elementId": element_id})


async def _get_element_text(session_id: str, element_id: str) -> list[types.TextContent]:
    data = await _get(f"/session/{session_id}/element/{element_id}/text")
    return _ok({"text": data.get("value", "")})


# ── actions ───────────────────────────────────────────────────────────────────

async def _press_key(session_id: str, keycode: int) -> list[types.TextContent]:
    actions = [
        {
            "type": "key",
            "id": "keyboard",
            "actions": [
                {"type": "keyDown", "value": chr(keycode)},
                {"type": "keyUp", "value": chr(keycode)},
            ],
        }
    ]
    # Prefer the Appium-specific pressKeyCode extension for reliability
    try:
        await _post(f"/session/{session_id}/appium/device/press_keycode", {"keycode": keycode})
    except httpx.HTTPStatusError:
        await _post(f"/session/{session_id}/actions", {"actions": actions})
    return _ok({"pressed": keycode})


async def _swipe(
    session_id: str,
    start_x: int,
    start_y: int,
    end_x: int,
    end_y: int,
    duration_ms: int,
) -> list[types.TextContent]:
    actions = [
        {
            "type": "pointer",
            "id": "finger",
            "parameters": {"pointerType": "touch"},
            "actions": [
                {"type": "pointerMove", "duration": 0, "x": start_x, "y": start_y},
                {"type": "pointerDown", "button": 0},
                {"type": "pointerMove", "duration": duration_ms, "x": end_x, "y": end_y},
                {"type": "pointerUp", "button": 0},
            ],
        }
    ]
    await _post(f"/session/{session_id}/actions", {"actions": actions})
    return _ok({"swipe": f"({start_x},{start_y}) → ({end_x},{end_y})"})


# ── app management ────────────────────────────────────────────────────────────

async def _install_app(session_id: str, app_path: str) -> list[types.TextContent]:
    await _post(f"/session/{session_id}/appium/device/install_app", {"appPath": app_path})
    return _ok({"installed": app_path})


async def _get_current_activity(session_id: str) -> list[types.TextContent]:
    pkg = await _get(f"/session/{session_id}/appium/device/current_package")
    act = await _get(f"/session/{session_id}/appium/device/current_activity")
    return _ok({
        "package": pkg.get("value", ""),
        "activity": act.get("value", ""),
    })


async def _execute_script(
    session_id: str, script: str, args: list
) -> list[types.TextContent]:
    data = await _post(f"/session/{session_id}/execute/sync", {"script": script, "args": args})
    return _ok({"result": data.get("value")})


# ── robot framework ───────────────────────────────────────────────────────────

async def _run_robot_tests(
    suite_path: str,
    variables: dict,
    output_dir: str,
    include_tags: list[str],
    exclude_tags: list[str],
) -> list[types.TextContent]:
    path = Path(suite_path)
    if not path.is_absolute():
        path = ROBOT_TESTS_DIR / suite_path

    if not path.exists():
        return _err(f"Suite not found: {path}")

    out = Path(output_dir)
    out.mkdir(parents=True, exist_ok=True)

    cmd = ["python", "-m", "robot", "--outputdir", str(out)]

    # inject APPIUM_URL so tests can pick it up
    cmd += ["-v", f"APPIUM_URL:{APPIUM_URL}"]

    for k, v in variables.items():
        cmd += ["-v", f"{k}:{v}"]
    for tag in include_tags:
        cmd += ["-i", tag]
    for tag in exclude_tags:
        cmd += ["-e", tag]

    cmd.append(str(path))

    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
    )
    stdout, _ = await proc.communicate()
    output = stdout.decode(errors="replace")

    return _ok({
        "returncode": proc.returncode,
        "passed": proc.returncode == 0,
        "output": output[-4000:] if len(output) > 4000 else output,
        "report": str(out / "report.html"),
    })


async def _list_robot_tests() -> list[types.TextContent]:
    if not ROBOT_TESTS_DIR.exists():
        return _err(f"Tests directory not found: {ROBOT_TESTS_DIR}")

    suites = sorted(ROBOT_TESTS_DIR.rglob("*.robot"))
    result = []
    for suite in suites:
        tests = []
        try:
            text = suite.read_text(errors="replace")
            in_tc = False
            for line in text.splitlines():
                stripped = line.strip()
                if stripped.startswith("*** Test Cases"):
                    in_tc = True
                    continue
                if stripped.startswith("***"):
                    in_tc = False
                    continue
                if in_tc and stripped and not stripped.startswith("#"):
                    # first non-indented line inside Test Cases = test name
                    if not line.startswith((" ", "\t")):
                        tests.append(stripped)
        except OSError:
            pass
        result.append({"file": str(suite.relative_to(ROBOT_TESTS_DIR)), "tests": tests})

    return _ok({"suites": result})


# ── entrypoint ─────────────────────────────────────────────────────────────────

async def main() -> None:
    async with stdio_server() as (read_stream, write_stream):
        await server.run(
            read_stream,
            write_stream,
            server.create_initialization_options(),
        )


if __name__ == "__main__":
    asyncio.run(main())
