import json
import compression.zstd
import tempfile
import threading
import unittest
import urllib.request
from unittest import mock
from pathlib import Path

import router


class RouterTests(unittest.TestCase):
    def test_zen_requests_use_non_blocked_user_agent(self):
        response = mock.MagicMock()
        response.status = 200
        response.headers.items.return_value = []
        response.read.return_value = b'{}'
        response.__enter__.return_value = response
        with mock.patch.object(router.urllib.request, "urlopen", return_value=response) as urlopen:
            router.post_json("https://opencode.ai/zen/v1/chat/completions", {}, {})
        self.assertEqual(urlopen.call_args.args[0].get_header("User-agent"), router.ZEN_USER_AGENT)

    def test_runtime_can_decode_codex_zstd_requests(self):
        payload = b'{"model":"gpt-5.6-terra"}'
        self.assertEqual(compression.zstd.decompress(compression.zstd.compress(payload)), payload)

    def test_catalog_keeps_native_and_only_adds_non_gpt_models(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.json"
            destination = Path(directory) / "merged.json"
            source.write_text(json.dumps({"models": [
                {"slug": "gpt-5.4-mini", "display_name": "GPT", "priority": 1, "visibility": "list", "tool_mode": "code_mode_only"},
                {"slug": "opencode-zen/stale", "display_name": "stale"},
            ]}))
            merged = router.generate_catalog(source, destination)
            slugs = [model["slug"] for model in merged["models"]]
            self.assertEqual(slugs, [
                "gpt-5.4-mini",
                "opencode-zen/deepseek-v4-pro",
                "opencode-zen/deepseek-v4-flash",
            ])
            self.assertNotIn("tool_mode", merged["models"][1])

    def test_custom_tool_round_trip(self):
        request = {
            "model": "opencode-zen/deepseek-v4-pro",
            "instructions": "Use tools.",
            "input": [{"type": "message", "role": "user", "content": [{"type": "input_text", "text": "patch it"}]}],
            "tools": [{"type": "custom", "name": "apply_patch", "description": "Patch files"}],
        }
        chat, freeform, tool_search, namespaces = router.responses_to_chat(request)
        self.assertEqual(chat["model"], "deepseek-v4-pro")
        self.assertEqual(chat["tools"][0]["function"]["parameters"]["required"], ["input"])
        response = {
            "choices": [{"message": {"tool_calls": [{
                "id": "call_1", "type": "function",
                "function": {"name": "apply_patch", "arguments": json.dumps({"input": "*** Begin Patch"})},
            }]}}],
            "usage": {"prompt_tokens": 10, "completion_tokens": 4, "total_tokens": 14},
        }
        events = router.chat_to_response_events(response, request["model"], freeform, tool_search, namespaces)
        done = next(data for name, data in events if name == "response.output_item.done")
        self.assertEqual(done["item"]["type"], "custom_tool_call")
        self.assertEqual(done["item"]["input"], "*** Begin Patch")
        self.assertEqual(events[-1][0], "response.completed")

    def test_native_model_cannot_enter_zen_translation(self):
        with self.assertRaises(ValueError):
            router.responses_to_chat({"model": "gpt-5.6-sol", "input": "hello"})

    def test_replayed_tool_call_and_output_become_chat_messages(self):
        chat, _, _, _ = router.responses_to_chat({
            "model": "opencode-zen/deepseek-v4-flash",
            "input": [
                {"type": "custom_tool_call", "call_id": "call_7", "name": "shell", "input": "pwd"},
                {"type": "custom_tool_call_output", "call_id": "call_7", "output": "'/tmp'"},
            ],
        })
        self.assertEqual(chat["messages"][0]["tool_calls"][0]["function"]["arguments"], '{"input": "pwd"}')
        self.assertEqual(chat["messages"][1], {"role": "tool", "tool_call_id": "call_7", "content": "'/tmp'"})

    def test_replayed_v2_compaction_becomes_summary_context(self):
        chat, _, _, _ = router.responses_to_chat({
            "model": "opencode-zen/deepseek-v4-pro",
            "input": [{"type": "compaction", "encrypted_content": "Prior progress."}],
        })
        self.assertEqual(chat["messages"], [{
            "role": "user",
            "content": f"{router.SUMMARY_PREFIX}\nPrior progress.",
        }])

    def test_compaction_uses_chat_completion_and_returns_codex_history(self):
        upstream_bodies = []

        def fake_post_json(_url, body, _headers):
            upstream_bodies.append(body)
            response = {"choices": [{"message": {"content": "Progress and next steps."}}]}
            return 200, {}, json.dumps(response).encode()

        server = router.QuietThreadingHTTPServer(("127.0.0.1", 0), router.RouterHandler)
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            payload = json.dumps({
                "model": "opencode-zen/deepseek-v4-pro",
                "input": [{
                    "type": "message",
                    "role": "user",
                    "content": [{"type": "input_text", "text": "Fix the bug."}],
                }],
                "tools": [{"type": "function", "name": "shell"}],
            }).encode()
            request = urllib.request.Request(
                f"http://127.0.0.1:{server.server_port}/v1/responses/compact",
                data=payload,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with mock.patch.object(router, "keychain_key", return_value="test-key"), \
                 mock.patch.object(router, "post_json", side_effect=fake_post_json):
                with urllib.request.urlopen(request, timeout=5) as response:
                    self.assertEqual(response.status, 200)
                    compacted = json.loads(response.read())
        finally:
            server.shutdown()
            server.server_close()
            worker.join(timeout=5)

        self.assertNotIn("tools", upstream_bodies[0])
        self.assertEqual(upstream_bodies[0]["messages"][-1]["content"], router.COMPACTION_PROMPT)
        summary = compacted["output"][0]
        self.assertEqual(summary["role"], "user")
        self.assertEqual(
            summary["content"][0]["text"],
            f"{router.SUMMARY_PREFIX}\nProgress and next steps.",
        )

    def test_v2_compaction_trigger_returns_one_compaction_item(self):
        upstream_bodies = []

        def fake_post_json(_url, body, _headers):
            upstream_bodies.append(body)
            response = {"choices": [{"message": {"content": "Progress and next steps."}}]}
            return 200, {}, json.dumps(response).encode()

        server = router.QuietThreadingHTTPServer(("127.0.0.1", 0), router.RouterHandler)
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            payload = json.dumps({
                "model": "opencode-zen/deepseek-v4-pro",
                "input": [
                    {
                        "type": "message",
                        "role": "user",
                        "content": [{"type": "input_text", "text": "Fix the bug."}],
                    },
                    {"type": "compaction_trigger"},
                ],
                "tools": [{"type": "function", "name": "shell"}],
            }).encode()
            request = urllib.request.Request(
                f"http://127.0.0.1:{server.server_port}/v1/responses",
                data=payload,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with mock.patch.object(router, "keychain_key", return_value="test-key"), \
                 mock.patch.object(router, "post_json", side_effect=fake_post_json):
                with urllib.request.urlopen(request, timeout=5) as response:
                    self.assertEqual(response.status, 200)
                    stream = response.read().decode()
        finally:
            server.shutdown()
            server.server_close()
            worker.join(timeout=5)

        events = [
            json.loads(line.removeprefix("data: "))
            for line in stream.splitlines()
            if line.startswith("data: {")
        ]
        output = [event["item"] for event in events if event["type"] == "response.output_item.done"]
        self.assertEqual([item["type"] for item in output], ["compaction"])
        self.assertEqual(output[0]["encrypted_content"], "Progress and next steps.")
        self.assertNotIn("tools", upstream_bodies[0])


if __name__ == "__main__":
    unittest.main()
