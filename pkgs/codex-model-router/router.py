#!/usr/bin/env python3
"""Route Codex Responses requests without changing its built-in OpenAI provider."""

from __future__ import annotations

import argparse
import copy
import compression.zstd
import getpass
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

LISTEN_HOST = "127.0.0.1"
LISTEN_PORT = 10101
NATIVE_BASE = os.environ.get("CODEX_NATIVE_BASE_URL", "https://chatgpt.com/backend-api/codex").rstrip("/")
ZEN_BASE = os.environ.get("OPENCODE_ZEN_BASE_URL", "https://opencode.ai/zen/v1").rstrip("/")
ZEN_PREFIX = "opencode-zen/"
KEYCHAIN_SERVICE = "codex-opencode-zen"
ZEN_USER_AGENT = "codex-model-router/0.1"
COMPACTION_PROMPT = """Create a concise handoff summary for another coding agent that will resume this task.

Include current progress, key decisions, constraints, user preferences, remaining work, and critical references. Do not call tools. Return only the handoff summary."""
SUMMARY_PREFIX = "Another language model started to solve this problem and produced a summary of its thinking process. You also have access to the state of the tools that were used by that language model. Use this to build on the work that has already been done and avoid duplicating work. Here is the summary produced by the other language model, use the information in this summary to assist with your own analysis:"
MODELS = (
    ("deepseek-v4-pro", "OpenCode DeepSeek V4 Pro", "DeepSeek V4 Pro through OpenCode Zen."),
    ("deepseek-v4-flash", "OpenCode DeepSeek V4 Flash", "DeepSeek V4 Flash through OpenCode Zen."),
)
MAX_BODY_BYTES = 32 * 1024 * 1024
FORWARD_HEADERS = (
    "Authorization", "ChatGPT-Account-Id", "OpenAI-Beta", "Originator", "Session_Id",
    "Session-Id", "Thread-Id", "X-Client-Request-Id", "X-Codex-Beta-Features",
    "X-Codex-Installation-Id", "X-Codex-Parent-Thread-Id", "X-Codex-Turn-Metadata",
    "X-Codex-Turn-State", "X-Codex-Window-Id", "X-OAI-Attestation",
    "X-OpenAI-Subagent", "X-ResponsesAPI-Include-Timing-Metrics", "User-Agent",
)


def home_path(relative: str) -> Path:
    return Path(os.environ.get("HOME", str(Path.home()))) / relative


def catalog_path() -> Path:
    return home_path(".codex/model-catalog-merged.json")


def native_catalog_path() -> Path:
    return home_path(".codex/models_cache.json")


def generate_catalog(source: Path | None = None, destination: Path | None = None) -> dict[str, Any]:
    source = source or native_catalog_path()
    destination = destination or catalog_path()
    data = json.loads(source.read_text())
    native = [m for m in data.get("models", []) if not str(m.get("slug", "")).startswith(ZEN_PREFIX)]
    if not native:
        raise ValueError("native model catalog is empty")
    template = next((m for m in native if m.get("slug") == "gpt-5.4-mini"), native[0])
    routed = []
    for offset, (slug, display_name, description) in enumerate(MODELS, start=1):
        model = copy.deepcopy(template)
        model.update(
            slug=f"{ZEN_PREFIX}{slug}",
            display_name=display_name,
            description=description,
            priority=100 + offset,
            visibility="list",
            context_window=128000,
            default_reasoning_level="medium",
            supported_reasoning_levels=[
                {"effort": "low", "description": "Faster responses"},
                {"effort": "medium", "description": "Balanced reasoning"},
                {"effort": "high", "description": "Deeper reasoning"},
            ],
        )
        for key in (
            "model_messages", "tool_mode", "multi_agent_version", "use_responses_lite",
            "supports_websockets", "service_tier", "supported_service_tiers", "default_service_tier",
        ):
            model.pop(key, None)
        routed.append(model)
    merged = dict(data)
    merged["models"] = native + routed
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(".tmp")
    temporary.write_text(json.dumps(merged, indent=2, ensure_ascii=False) + "\n")
    os.chmod(temporary, 0o600)
    temporary.replace(destination)
    return merged


def keychain_key() -> str:
    account = os.environ.get("USER", "tt")
    result = subprocess.run(
        ["/usr/bin/security", "find-generic-password", "-a", account, "-s", KEYCHAIN_SERVICE, "-w"],
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0 or not result.stdout.strip():
        raise RuntimeError("OpenCode Zen credential is not configured; run: codex-model-router set-zen-key")
    return result.stdout.strip()


def set_keychain_key() -> None:
    if sys.platform != "darwin":
        raise RuntimeError("macOS Keychain is required")
    value = getpass.getpass("OpenCode Zen key: ").strip()
    if not value:
        raise RuntimeError("empty key was not stored")
    account = os.environ.get("USER", "tt")
    subprocess.run(
        ["/usr/bin/security", "add-generic-password", "-U", "-a", account, "-s", KEYCHAIN_SERVICE, "-w", value],
        check=True,
    )
    print("OpenCode Zen credential stored in macOS Keychain.")


def text_content(content: Any) -> Any:
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return ""
    parts: list[dict[str, Any]] = []
    for part in content:
        if not isinstance(part, dict):
            continue
        kind = part.get("type")
        if kind in ("input_text", "output_text", "text") and isinstance(part.get("text"), str):
            parts.append({"type": "text", "text": part["text"]})
        elif kind == "input_image" and isinstance(part.get("image_url"), str):
            parts.append({"type": "image_url", "image_url": {"url": part["image_url"]}})
    if len(parts) == 1 and parts[0]["type"] == "text":
        return parts[0]["text"]
    return parts


def responses_to_chat(body: dict[str, Any]) -> tuple[dict[str, Any], set[str], set[str], dict[str, tuple[str, str]]]:
    messages: list[dict[str, Any]] = []
    instructions = body.get("instructions")
    if isinstance(instructions, str) and instructions:
        messages.append({"role": "system", "content": instructions})
    raw_input = body.get("input", [])
    if isinstance(raw_input, str):
        messages.append({"role": "user", "content": raw_input})
        raw_input = []
    pending_calls: list[dict[str, Any]] = []

    def flush_calls() -> None:
        nonlocal pending_calls
        if pending_calls:
            messages.append({"role": "assistant", "content": None, "tool_calls": pending_calls})
            pending_calls = []

    if isinstance(raw_input, list):
        for item in raw_input:
            if not isinstance(item, dict):
                continue
            kind = item.get("type")
            if kind == "message":
                flush_calls()
                messages.append({"role": item.get("role", "user"), "content": text_content(item.get("content"))})
            elif kind in ("function_call", "custom_tool_call"):
                args = item.get("arguments", "{}")
                if kind == "custom_tool_call":
                    args = json.dumps({"input": item.get("input", "")})
                pending_calls.append({
                    "id": item.get("call_id") or item.get("id") or f"call_{uuid.uuid4().hex}",
                    "type": "function",
                    "function": {"name": item.get("name", ""), "arguments": args or "{}"},
                })
            elif kind in ("function_call_output", "custom_tool_call_output", "tool_search_call_output"):
                flush_calls()
                messages.append({
                    "role": "tool",
                    "tool_call_id": item.get("call_id") or item.get("id") or "",
                    "content": text_content(item.get("output", "")),
                })
            elif kind in ("compaction", "compaction_summary", "context_compaction"):
                flush_calls()
                summary = item.get("encrypted_content")
                if isinstance(summary, str) and summary:
                    messages.append({"role": "user", "content": f"{SUMMARY_PREFIX}\n{summary}"})
        flush_calls()

    chat_tools: list[dict[str, Any]] = []
    freeform: set[str] = set()
    tool_search: set[str] = set()
    namespaces: dict[str, tuple[str, str]] = {}

    def add_function(tool: dict[str, Any], namespace: str | None = None) -> None:
        name = str(tool.get("name", ""))
        wire_name = f"{namespace}__{name}" if namespace else name
        if namespace:
            namespaces[wire_name] = (namespace, name)
        params = tool.get("parameters")
        if not isinstance(params, dict):
            params = {"type": "object", "properties": {}}
        chat_tools.append({"type": "function", "function": {
            "name": wire_name,
            "description": tool.get("description", ""),
            "parameters": params,
        }})

    for tool in body.get("tools", []) if isinstance(body.get("tools"), list) else []:
        if not isinstance(tool, dict):
            continue
        kind = tool.get("type")
        if kind == "function" and isinstance(tool.get("name"), str):
            add_function(tool)
        elif kind == "namespace" and isinstance(tool.get("tools"), list):
            for inner in tool["tools"]:
                if isinstance(inner, dict) and inner.get("type") == "function":
                    add_function(inner, str(tool.get("name", "namespace")))
        elif kind == "custom" and isinstance(tool.get("name"), str):
            name = tool["name"]
            freeform.add(name)
            chat_tools.append({"type": "function", "function": {
                "name": name,
                "description": tool.get("description", ""),
                "parameters": {"type": "object", "properties": {"input": {"type": "string"}}, "required": ["input"]},
            }})
        elif kind == "tool_search":
            tool_search.add("tool_search")
            add_function({
                "name": "tool_search",
                "description": tool.get("description", "Search for additional tools."),
                "parameters": tool.get("parameters", {"type": "object", "properties": {"query": {"type": "string"}}, "required": ["query"]}),
            })

    model = str(body.get("model", ""))
    if not model.startswith(ZEN_PREFIX):
        raise ValueError("third-party model is not namespaced")
    chat: dict[str, Any] = {
        "model": model.removeprefix(ZEN_PREFIX),
        "messages": messages,
        "stream": False,
    }
    if chat_tools:
        chat["tools"] = chat_tools
        chat["parallel_tool_calls"] = body.get("parallel_tool_calls", True)
    if isinstance(body.get("max_output_tokens"), int):
        chat["max_tokens"] = body["max_output_tokens"]
    if isinstance(body.get("temperature"), (int, float)):
        chat["temperature"] = body["temperature"]
    choice = body.get("tool_choice")
    if choice in ("auto", "none", "required"):
        chat["tool_choice"] = choice
    return chat, freeform, tool_search, namespaces


def compact_to_chat(body: dict[str, Any]) -> dict[str, Any]:
    chat, _, _, _ = responses_to_chat(body)
    chat.pop("tools", None)
    chat.pop("parallel_tool_calls", None)
    chat.pop("tool_choice", None)
    chat["messages"].append({"role": "user", "content": COMPACTION_PROMPT})
    return chat


def chat_to_compact_response(chat: dict[str, Any]) -> dict[str, Any]:
    choices = chat.get("choices")
    if not isinstance(choices, list) or not choices:
        raise ValueError("upstream response has no choices")
    message = choices[0].get("message", {}) if isinstance(choices[0], dict) else {}
    summary = message.get("content") if isinstance(message, dict) else None
    if not isinstance(summary, str) or not summary.strip():
        raise ValueError("upstream compaction response has no summary")
    return {"output": [{
        "type": "message",
        "role": "user",
        "content": [{"type": "input_text", "text": f"{SUMMARY_PREFIX}\n{summary.strip()}"}],
    }]}


def chat_to_compaction_events(chat: dict[str, Any], model: str) -> list[tuple[str, dict[str, Any]]]:
    choices = chat.get("choices")
    if not isinstance(choices, list) or not choices:
        raise ValueError("upstream response has no choices")
    message = choices[0].get("message", {}) if isinstance(choices[0], dict) else {}
    summary = message.get("content") if isinstance(message, dict) else None
    if not isinstance(summary, str) or not summary.strip():
        raise ValueError("upstream compaction response has no summary")

    response_id = f"resp_{uuid.uuid4().hex}"
    item = {
        "type": "compaction",
        "id": f"cmp_{uuid.uuid4().hex}",
        "encrypted_content": summary.strip(),
    }
    snapshot = {
        "id": response_id,
        "object": "response",
        "created_at": int(time.time()),
        "status": "in_progress",
        "model": model,
        "output": [],
        "usage": None,
    }
    completed = {
        **snapshot,
        "status": "completed",
        "output": [item],
        "usage": usage(chat.get("usage")),
    }
    return [
        ("response.created", {"type": "response.created", "sequence_number": 0, "response": snapshot}),
        ("response.output_item.added", {
            "type": "response.output_item.added",
            "sequence_number": 1,
            "output_index": 0,
            "item": item,
        }),
        ("response.output_item.done", {
            "type": "response.output_item.done",
            "sequence_number": 2,
            "output_index": 0,
            "item": item,
        }),
        ("response.completed", {
            "type": "response.completed",
            "sequence_number": 3,
            "response": completed,
        }),
    ]


def usage(raw: Any) -> dict[str, Any]:
    raw = raw if isinstance(raw, dict) else {}
    input_tokens = int(raw.get("prompt_tokens", 0) or 0)
    output_tokens = int(raw.get("completion_tokens", 0) or 0)
    return {
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        "total_tokens": int(raw.get("total_tokens", input_tokens + output_tokens) or 0),
        "input_tokens_details": {"cached_tokens": 0},
        "output_tokens_details": {"reasoning_tokens": 0},
    }


def chat_to_response_events(chat: dict[str, Any], model: str, freeform: set[str], tool_search: set[str], namespaces: dict[str, tuple[str, str]]) -> list[tuple[str, dict[str, Any]]]:
    response_id = f"resp_{uuid.uuid4().hex}"
    created_at = int(time.time())
    output: list[dict[str, Any]] = []
    events: list[tuple[str, dict[str, Any]]] = []
    sequence = 0

    def emit(name: str, payload: dict[str, Any]) -> None:
        nonlocal sequence
        events.append((name, {"type": name, "sequence_number": sequence, **payload}))
        sequence += 1

    snapshot = {"id": response_id, "object": "response", "created_at": created_at, "status": "in_progress", "model": model, "output": [], "usage": None}
    emit("response.created", {"response": snapshot})
    choices = chat.get("choices")
    if not isinstance(choices, list) or not choices:
        raise ValueError("upstream response has no choices")
    message = choices[0].get("message", {}) if isinstance(choices[0], dict) else {}
    content = message.get("content") if isinstance(message, dict) else None
    if isinstance(content, str) and content:
        index = len(output)
        item_id = f"msg_{uuid.uuid4().hex}"
        added = {"type": "message", "id": item_id, "status": "in_progress", "role": "assistant", "content": []}
        emit("response.output_item.added", {"output_index": index, "item": added})
        emit("response.content_part.added", {"item_id": item_id, "output_index": index, "content_index": 0, "part": {"type": "output_text", "text": "", "annotations": []}})
        emit("response.output_text.delta", {"item_id": item_id, "output_index": index, "content_index": 0, "delta": content})
        emit("response.output_text.done", {"item_id": item_id, "output_index": index, "content_index": 0, "text": content})
        part = {"type": "output_text", "text": content, "annotations": []}
        emit("response.content_part.done", {"item_id": item_id, "output_index": index, "content_index": 0, "part": part})
        done = {"type": "message", "id": item_id, "status": "completed", "role": "assistant", "content": [part], "phase": "final_answer"}
        emit("response.output_item.done", {"output_index": index, "item": done})
        output.append(done)
    calls = message.get("tool_calls", []) if isinstance(message, dict) else []
    if isinstance(calls, list):
        for call in calls:
            if not isinstance(call, dict):
                continue
            function = call.get("function", {})
            if not isinstance(function, dict):
                continue
            wire_name = str(function.get("name", ""))
            namespace, name = namespaces.get(wire_name, ("", wire_name))
            arguments = str(function.get("arguments", "{}") or "{}")
            call_id = str(call.get("id") or f"call_{uuid.uuid4().hex}")
            index = len(output)
            if name in freeform:
                item_id = f"ctc_{uuid.uuid4().hex}"
                try:
                    decoded = json.loads(arguments)
                    raw_input = decoded.get("input", arguments) if isinstance(decoded, dict) else arguments
                except json.JSONDecodeError:
                    raw_input = arguments
                added = {"type": "custom_tool_call", "id": item_id, "call_id": call_id, "name": name, "input": "", "status": "in_progress"}
                emit("response.output_item.added", {"output_index": index, "item": added})
                emit("response.custom_tool_call_input.delta", {"item_id": item_id, "output_index": index, "delta": raw_input})
                emit("response.custom_tool_call_input.done", {"item_id": item_id, "output_index": index, "input": raw_input})
                done = {**added, "input": raw_input, "status": "completed"}
            elif name in tool_search:
                item_id = f"tsc_{uuid.uuid4().hex}"
                try:
                    parsed_args = json.loads(arguments)
                except json.JSONDecodeError:
                    parsed_args = {}
                added = {"type": "tool_search_call", "id": item_id, "call_id": call_id, "execution": "client", "arguments": {}, "status": "in_progress"}
                emit("response.output_item.added", {"output_index": index, "item": added})
                done = {**added, "arguments": parsed_args, "status": "completed"}
            else:
                item_id = f"fc_{uuid.uuid4().hex}"
                added = {"type": "function_call", "id": item_id, "call_id": call_id, "name": name, "arguments": "", "status": "in_progress"}
                if namespace:
                    added["namespace"] = namespace
                emit("response.output_item.added", {"output_index": index, "item": added})
                emit("response.function_call_arguments.delta", {"item_id": item_id, "output_index": index, "delta": arguments})
                emit("response.function_call_arguments.done", {"item_id": item_id, "output_index": index, "arguments": arguments})
                done = {**added, "arguments": arguments, "status": "completed"}
            emit("response.output_item.done", {"output_index": index, "item": done})
            output.append(done)
    completed = {**snapshot, "status": "completed", "output": output, "usage": usage(chat.get("usage"))}
    emit("response.completed", {"response": completed})
    return events


def post_json(url: str, body: dict[str, Any], headers: dict[str, str]) -> tuple[int, dict[str, str], bytes]:
    request_headers = {**headers, "User-Agent": ZEN_USER_AGENT}
    request = urllib.request.Request(url, data=json.dumps(body).encode(), headers=request_headers, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=600) as response:
            return response.status, dict(response.headers.items()), response.read()
    except urllib.error.HTTPError as error:
        return error.code, dict(error.headers.items()), error.read()


class RouterHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, _format: str, *_args: Any) -> None:
        return

    def error(self, status: int, message: str, error_type: str = "invalid_request_error") -> None:
        payload = json.dumps({"error": {"message": message, "type": error_type}}).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def reject_websocket(self) -> bool:
        if self.headers.get("Upgrade", "").lower() != "websocket":
            return False
        self.send_response(426)
        self.send_header("Connection", "close")
        self.send_header("Content-Length", "0")
        self.end_headers()
        self.close_connection = True
        return True

    def do_GET(self) -> None:
        if self.reject_websocket():
            return
        if self.path == "/health":
            payload = b'{"ok":true}'
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        else:
            self.error(404, "not found")

    def do_POST(self) -> None:
        if self.reject_websocket():
            return
        try:
            size = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            return self.error(400, "invalid content length")
        if size <= 0 or size > MAX_BODY_BYTES:
            return self.error(413, "request body is empty or too large")
        raw = self.rfile.read(size)
        decoded = raw
        content_encoding = self.headers.get("Content-Encoding", "").lower()
        try:
            if content_encoding == "zstd":
                decoded = compression.zstd.decompress(raw)
            elif content_encoding not in ("", "identity"):
                return self.error(415, f"unsupported content encoding: {content_encoding}")
            body = json.loads(decoded)
        except (json.JSONDecodeError, UnicodeDecodeError, compression.zstd.ZstdError):
            return self.error(400, "invalid JSON")
        if not isinstance(body, dict):
            return self.error(400, "JSON object required")
        model = str(body.get("model", ""))
        if model.startswith(ZEN_PREFIX):
            return self.route_zen(body, model)
        return self.route_native(raw, content_encoding)

    def route_native(self, raw: bytes, content_encoding: str) -> None:
        if not self.path.startswith("/v1/"):
            return self.error(404, "native route not found")
        suffix = self.path.removeprefix("/v1")
        headers = {"Content-Type": self.headers.get("Content-Type", "application/json")}
        if content_encoding:
            headers["Content-Encoding"] = content_encoding
        for name in FORWARD_HEADERS:
            value = self.headers.get(name)
            if value:
                headers[name] = value
        request = urllib.request.Request(f"{NATIVE_BASE}{suffix}", data=raw, headers=headers, method="POST")
        try:
            response = urllib.request.urlopen(request, timeout=600)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            self.send_response(response.status)
            self.send_header("Content-Type", response.headers.get("Content-Type", "application/json"))
            for name in ("OpenAI-Model", "X-Request-Id", "Retry-After", "X-Codex-Primary-Reset-At", "X-Codex-Secondary-Reset-At", "X-Codex-Tertiary-Reset-At"):
                value = response.headers.get(name)
                if value:
                    self.send_header(name, value)
            self.send_header("Cache-Control", response.headers.get("Cache-Control", "no-cache"))
            self.send_header("Connection", "close")
            self.end_headers()
            while chunk := response.read(64 * 1024):
                self.wfile.write(chunk)
                self.wfile.flush()
            self.close_connection = True

    def route_zen(self, body: dict[str, Any], model: str) -> None:
        if self.path == "/v1/responses/compact":
            return self.route_zen_compact(body, model)
        if self.path != "/v1/responses":
            return self.error(404, "OpenCode Zen only supports /v1/responses and /v1/responses/compact")
        raw_input = body.get("input")
        if isinstance(raw_input, list) and any(
            isinstance(item, dict) and item.get("type") == "compaction_trigger"
            for item in raw_input
        ):
            return self.route_zen_compact_v2(body, model)
        if model.removeprefix(ZEN_PREFIX) not in {entry[0] for entry in MODELS}:
            return self.error(400, "OpenCode Zen model is not allowed")
        try:
            chat_body, freeform, tool_search, namespaces = responses_to_chat(body)
            key = keychain_key()
        except (ValueError, RuntimeError) as error:
            return self.error(400, str(error))
        status, response_headers, raw = post_json(
            f"{ZEN_BASE}/chat/completions",
            chat_body,
            {"Content-Type": "application/json", "Authorization": f"Bearer {key}"},
        )
        if status >= 400:
            self.send_response(status)
            self.send_header("Content-Type", response_headers.get("Content-Type", "application/json"))
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)
            return
        try:
            chat = json.loads(raw)
            events = chat_to_response_events(chat, model, freeform, tool_search, namespaces)
        except (json.JSONDecodeError, ValueError) as error:
            return self.error(502, f"invalid OpenCode Zen response: {error}", "upstream_error")
        frames = []
        for name, event in events:
            frames.append(f"event: {name}\ndata: {json.dumps(event, separators=(',', ':'))}\n\n")
        frames.append("data: [DONE]\n\n")
        payload = "".join(frames).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def route_zen_compact_v2(self, body: dict[str, Any], model: str) -> None:
        if model.removeprefix(ZEN_PREFIX) not in {entry[0] for entry in MODELS}:
            return self.error(400, "OpenCode Zen model is not allowed")
        try:
            chat_body = compact_to_chat(body)
            key = keychain_key()
        except (ValueError, RuntimeError) as error:
            return self.error(400, str(error))
        status, response_headers, raw = post_json(
            f"{ZEN_BASE}/chat/completions",
            chat_body,
            {"Content-Type": "application/json", "Authorization": f"Bearer {key}"},
        )
        if status >= 400:
            self.send_response(status)
            self.send_header("Content-Type", response_headers.get("Content-Type", "application/json"))
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)
            return
        try:
            events = chat_to_compaction_events(json.loads(raw), model)
        except (json.JSONDecodeError, ValueError) as error:
            return self.error(502, f"invalid OpenCode Zen compaction response: {error}", "upstream_error")
        frames = [
            f"event: {name}\ndata: {json.dumps(event, separators=(',', ':'))}\n\n"
            for name, event in events
        ]
        frames.append("data: [DONE]\n\n")
        payload = "".join(frames).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def route_zen_compact(self, body: dict[str, Any], model: str) -> None:
        if model.removeprefix(ZEN_PREFIX) not in {entry[0] for entry in MODELS}:
            return self.error(400, "OpenCode Zen model is not allowed")
        try:
            chat_body = compact_to_chat(body)
            key = keychain_key()
        except (ValueError, RuntimeError) as error:
            return self.error(400, str(error))
        status, response_headers, raw = post_json(
            f"{ZEN_BASE}/chat/completions",
            chat_body,
            {"Content-Type": "application/json", "Authorization": f"Bearer {key}"},
        )
        if status >= 400:
            self.send_response(status)
            self.send_header("Content-Type", response_headers.get("Content-Type", "application/json"))
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)
            return
        try:
            payload = json.dumps(chat_to_compact_response(json.loads(raw))).encode()
        except (json.JSONDecodeError, ValueError) as error:
            return self.error(502, f"invalid OpenCode Zen compaction response: {error}", "upstream_error")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


class QuietThreadingHTTPServer(ThreadingHTTPServer):
    def handle_error(self, request: Any, client_address: Any) -> None:
        if isinstance(sys.exception(), (ConnectionResetError, BrokenPipeError)):
            return
        super().handle_error(request, client_address)


def serve() -> None:
    generate_catalog()
    server = QuietThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), RouterHandler)
    server.serve_forever()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("serve", "generate-catalog", "set-zen-key"), nargs="?", default="serve")
    args = parser.parse_args()
    if args.command == "serve":
        serve()
    elif args.command == "generate-catalog":
        merged = generate_catalog()
        print(f"Wrote {catalog_path()} with {len(merged['models'])} models.")
    else:
        set_keychain_key()


if __name__ == "__main__":
    main()
