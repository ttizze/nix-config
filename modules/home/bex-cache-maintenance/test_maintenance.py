import contextlib
import fcntl
import io
import json
import os
import pathlib
import tempfile
import time
import unittest
from unittest import mock

import maintenance as m


class MaintenanceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.home = pathlib.Path(self.temporary.name).resolve()
        self.store = self.home / ".cargo"
        self.remote = self.home / ".cache/agent-remote-builds"
        self.remote.mkdir(parents=True)
        self.now = time.time()
        self.device = self.home.stat().st_dev
        self.scanner = m.inspect_processes
        self.addCleanup(mock.patch.stopall)
        mock.patch.object(m, "inspect_processes", return_value=[]).start()
        mock.patch.object(m, "mount_points", return_value=[]).start()
        self.output = io.StringIO()
        redirect = contextlib.redirect_stdout(self.output)
        redirect.__enter__()
        self.addCleanup(redirect.__exit__, None, None, None)

    def cache(self, name="nsh-old", age=3 * 86400):
        root = self.home / ".cache" / name
        target = root / "target"
        target.mkdir(parents=True)
        (root / "source.rs").write_text("unfinished source")
        (target / "CACHEDIR.TAG").write_bytes(m.CACHE_SIGNATURE)
        (target / "binary").write_bytes(bytes(1024 * 1024))
        self.age(target, age)
        return target

    def age(self, path, age):
        for item in [*path.rglob("*"), path]:
            os.utime(item, (self.now - age, self.now - age), follow_symlinks=False)

    def candidate(self, target):
        return m.Candidate("target", target, (str(target.parent),), None, None, None)

    def clean(self, candidates, dry_run=False):
        return m.clean_candidates(candidates, self.device, self.now - 2 * 86400, dry_run)

    def test_expired_outputs_removed_while_source_is_preserved(self):
        target = self.cache()
        counts, _ = self.clean([self.candidate(target)])
        self.assertEqual(counts, {"target": 1})
        self.assertFalse(target.exists())
        self.assertEqual((target.parent / "source.rs").read_text(), "unfinished source")

    def test_active_process_and_locked_remote_target_are_preserved(self):
        target = self.cache()
        with mock.patch.object(m, "inspect_processes", return_value=[str(target.parent)]):
            _, skipped = self.clean([self.candidate(target)])
        self.assertEqual(skipped, {"active_reference": 1})
        lock = self.home / "worktree.lock"
        with lock.open("w") as held:
            fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
            _, skipped = self.clean([self.candidate(target)._replace(lock=lock)])
        self.assertEqual(skipped, {"locked_or_missing_lock": 1})
        self.assertTrue(target.exists())

    def test_recent_contents_and_last_used_marker_are_preserved(self):
        target = self.cache()
        (target / "binary").touch()
        self.assertFalse(self.clean([self.candidate(target)])[0])
        self.age(target, 3 * 86400)
        (target / ".last-used").touch()
        self.assertFalse(self.clean([self.candidate(target)])[0])
        self.assertTrue(target.exists())

    def test_nested_checkout_survives_while_its_old_generated_cache_expires(self):
        target = self.cache()
        checkout = target / "experiment/source/.git"
        checkout.mkdir(parents=True)
        cache = target / "tool-cache"
        cache.mkdir()
        (cache / "compiled").write_bytes(bytes(1024))
        self.age(target, 3 * 86400)
        candidates = m.collect_candidates(self.store, self.remote)
        self.clean(candidates)
        self.assertTrue(checkout.exists())
        self.assertFalse(cache.exists())

    def test_legacy_cargo_metadata_recognizes_outputs_without_a_tag(self):
        target = self.cache()
        (target / "CACHEDIR.TAG").unlink()
        info = target / ".rustc_info.json"
        info.write_text(json.dumps({"rustc_fingerprint": 1}))
        self.age(target, 3 * 86400)
        self.assertEqual(self.clean([self.candidate(target)])[0], {"target": 1})

    def test_unrecognized_directory_symlink_and_live_mutant_source_survive(self):
        target = self.cache()
        (target / "CACHEDIR.TAG").unlink()
        (target / ".rustc_info.json").write_text("[]")
        self.age(target, 3 * 86400)
        self.assertFalse(self.clean([self.candidate(target)])[0])
        tagged = self.cache("nsh-tagged")
        source = self.home / "mutant-source"
        source.mkdir()
        self.assertFalse(self.clean([self.candidate(tagged)._replace(source=source)])[0])
        link = self.home / "target-link"
        link.symlink_to(tagged)
        self.assertFalse(self.clean([self.candidate(link)])[0])
        self.assertTrue(tagged.exists())

    def test_dry_run_and_new_source_during_inspection_do_not_delete(self):
        target = self.cache()
        self.assertEqual(self.clean([self.candidate(target)], True)[0], {"target": 1})
        self.assertTrue(target.exists())

        def create_source():
            (target / "nested/.git").mkdir(parents=True)
            return []

        with mock.patch.object(m, "inspect_processes", side_effect=create_source):
            self.assertFalse(self.clean([self.candidate(target)])[0])
        self.assertTrue((target / "nested/.git").exists())

    def test_budget_evicts_idle_outputs_but_retains_current_outputs(self):
        idle = self.cache("nsh-idle", 86400)
        current = self.cache("nsh-current", 3600)
        candidates = m.collect_candidates(self.store, self.remote)
        roots = [candidate.path for candidate in candidates]
        m.clean_budget(candidates, roots, self.device, m.allocated_bytes([current]), False, self.now)
        self.assertFalse(idle.exists())
        self.assertTrue(current.exists())

    def test_budget_dry_run_lists_idle_eviction_without_deleting(self):
        target = self.cache(age=86400)
        m.clean_budget([self.candidate(target)], [target], self.device, 1, True, self.now)
        self.assertTrue(target.exists())
        events = [json.loads(line) for line in self.output.getvalue().splitlines()]
        self.assertTrue(any(event["event"] == "would_remove" for event in events))

    def test_recent_ten_worktrees_are_not_permanently_exempt_from_expiration(self):
        for number in range(11):
            key = format(number, "040x")
            (self.remote / (key + ".marker")).touch()
        candidates = m.collect_candidates(self.store, self.remote)
        self.assertEqual(sum(candidate.kind == "remote" for candidate in candidates), 11)

    def test_nested_roots_and_hard_links_are_counted_once(self):
        target = self.cache()
        nested = target / "child"
        nested.mkdir()
        os.link(target / "binary", nested / "publication")
        self.assertEqual(m.allocated_bytes([target, nested]), m.allocated_bytes([target]))

    def test_process_references_include_working_directory_and_open_files(self):
        process = self.home / "proc/1234"
        (process / "fd").mkdir(parents=True)
        (process / "cwd").symlink_to(self.home / "worktree")
        (process / "fd/3").symlink_to(self.home / "compiled")
        (process / "cmdline").write_bytes(b"rustc\0--crate-name\0fixture")
        reference = m.process_reference(process, strict=True)
        self.assertIn(str(self.home / "worktree"), reference)
        self.assertIn(str(self.home / "compiled"), reference)

    def test_unreadable_live_build_blocks_cleanup_but_exited_process_does_not(self):
        process = self.home / "proc/1234"
        process.mkdir(parents=True)
        (process / "comm").write_text("rustc")
        (process / "stat").write_text("1234 (rustc) S 0")
        with mock.patch.object(m, "process_reference", side_effect=PermissionError()):
            scanner = self.scanner
            with self.assertRaises(RuntimeError):
                scanner(process.parent)
            (process / "stat").write_text("1234 (rustc) Z 0")
            self.assertEqual(scanner(process.parent), [])


if __name__ == "__main__":
    unittest.main()
