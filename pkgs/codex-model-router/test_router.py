import json
import compression.zstd
import tempfile
import unittest
from pathlib import Path

import router


class RouterTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
