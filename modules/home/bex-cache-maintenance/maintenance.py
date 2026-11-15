import argparse
import collections
import contextlib
import fcntl
import json
import os
import pathlib
import re
import stat
import subprocess
import sys
import time


CACHE_SIGNATURE = b"Signature: 8a477f597d28d172789f06886806bc55"
ROOT_UUID = "6a0b6df1-b927-4351-bed9-00c713d6f9c2"
BUILD_NAMES = {"cargo", ".cargo-wrapped", "rustc", "cargo-nextest", "cargo-mutants", "nix-build", "rsync"}
MUTATION_NAME = re.compile(r"cargo-mutants-[0-9a-f]{40}-[A-Za-z0-9]+\.tmp-[0-9a-f]{8}")
Candidate = collections.namedtuple("Candidate", "kind path tokens marker lock source cache_root", defaults=[None])


def emit(event, **values):
    print(json.dumps({"event": event, **values}), flush=True)


def validate_mounts(store, remote):
    root = pathlib.Path("/")
    identity = subprocess.check_output(
        ["findmnt", "-n", "-T", "/", "-o", "FSTYPE,UUID"], text=True
    ).split()
    if identity != ["ext4", ROOT_UUID]:
        raise RuntimeError("Unexpected Ubuntu root filesystem")
    for path in (store, remote):
        if path.is_symlink() or path.resolve(strict=True) != path or not path.is_dir():
            raise RuntimeError("Unexpected build-storage path: " + str(path))
        if path.stat().st_dev != root.stat().st_dev:
            raise RuntimeError("Build storage is outside the relocated Ubuntu filesystem")


def mount_points():
    points = []
    for line in pathlib.Path("/proc/self/mountinfo").read_text().splitlines():
        value = re.sub(r"\\([0-7]{3})", lambda match: chr(int(match.group(1), 8)), line.split()[4])
        points.append(pathlib.Path(value))
    return points


def process_value(path, strict, link=False):
    try:
        return os.readlink(path) if link else path.read_bytes().decode("utf-8", "replace")
    except (FileNotFoundError, ProcessLookupError):
        return ""
    except PermissionError:
        if strict:
            raise
        return ""


def process_reference(process, strict):
    values = [process_value(process / name, strict) for name in ("cmdline", "environ", "maps")]
    try:
        descriptors = list((process / "fd").iterdir())
    except (FileNotFoundError, ProcessLookupError):
        descriptors = []
    except PermissionError:
        if strict:
            raise
        descriptors = []
    values += [process_value(path, strict, link=True) for path in (process / "cwd", process / "exe", *descriptors)]
    return "\n".join(values)


def inspect_processes(proc_root=pathlib.Path("/proc")):
    references = []
    for process in proc_root.iterdir():
        if not process.name.isdecimal() or int(process.name) == os.getpid():
            continue
        name = process_value(process / "comm", strict=False).strip()
        try:
            references.append(process_reference(process, name in BUILD_NAMES))
        except PermissionError as error:
            state = process_value(process / "stat", strict=True)
            if not state or state.rsplit(")", 1)[1].split()[0] in {"Z", "X", "x"}:
                continue
            raise RuntimeError("Cannot safely inspect process " + process.name) from error
    return references


def collect_candidates(store, remote, temporary=pathlib.Path("/tmp")):
    candidates = []
    fork = store / "targets"
    if fork.exists():
        if fork.is_symlink() or fork.resolve(strict=True) != fork:
            raise RuntimeError("Unexpected fork-target root")
        for path in fork.iterdir():
            if MUTATION_NAME.fullmatch(path.name):
                source_name = path.name.rsplit("-", 1)[0]
                candidates.append(Candidate("mutation", path, (path.name, source_name), None, None, temporary / source_name))
    markers = []
    for marker in remote.glob("*.marker"):
        if re.fullmatch(r"[0-9a-f]{40}\.marker", marker.name) and stat.S_ISREG(marker.lstat().st_mode):
            markers.append(marker)
    for marker in markers:
        key = marker.stem
        candidates.append(Candidate("remote", remote / key / "target", (key,), marker, remote / (key + ".lock"), None))
    home = store.parent
    targets = list((home / ".cache").glob("nsh-*/target"))
    repository = home / "ghq/github.com/ttizze/remote-agent"
    if repository.exists():
        listing = subprocess.check_output(["git", "-C", str(repository), "worktree", "list", "--porcelain", "-z"], text=True)
        targets += [pathlib.Path(part[9:]) / "target" for part in listing.split("\0") if part.startswith("worktree ")]
    candidates += [Candidate("target", target, (str(target.parent),), None, None, None) for target in targets]
    for candidate in list(candidates):
        # Preserve nested source checkouts while expiring their generated caches.
        caches = [candidate.path / "tool-cache"] + list((candidate.path / ".relax-experiment").glob("*"))
        for cache in caches:
            if cache.is_dir():
                candidates.append(candidate._replace(kind="experiment", path=cache, cache_root=candidate.path))
    return sorted({candidate.path: candidate for candidate in candidates}.values(), key=last_used)


def last_used(candidate):
    paths = [candidate.path, candidate.path / ".last-used"]
    if candidate.marker is not None:
        paths.append(candidate.marker)
    return max((path.stat().st_mtime for path in paths if path.exists()), default=0)


def storage_roots(paths):
    roots = []
    for path in sorted(set(paths), key=lambda item: len(item.parts)):
        if path.exists() and not any(parent in path.parents for parent in roots):
            roots.append(path)
    return roots


def allocated_bytes(paths):
    roots = storage_roots(paths)
    if not roots:
        return 0
    # A single invocation counts hard-linked Cargo publications only once.
    output = subprocess.check_output(["du", "-skx", "--", *map(str, roots)], text=True)
    return sum(int(line.split("\t", 1)[0]) * 1024 for line in output.splitlines())


def recognized_cache(path):
    tag = path / "CACHEDIR.TAG"
    if tag.is_file() and not tag.is_symlink() and tag.read_bytes().startswith(CACHE_SIGNATURE):
        return True
    # Some older Cargo versions omitted the tag; require Cargo's own metadata.
    info = path / ".rustc_info.json"
    if not info.is_file() or info.is_symlink():
        return False
    try:
        metadata = json.loads(info.read_text())
        return isinstance(metadata, dict) and "rustc_fingerprint" in metadata
    except (ValueError, UnicodeError):
        return False


def guard_candidate(candidate, device, cutoff):
    path = candidate.path
    if not os.path.lexists(path):
        return "already_absent"
    if path.is_symlink() or not path.is_dir() or path.resolve(strict=True) != path:
        return "path_guard"
    if path.stat().st_dev != device:
        return "wrong_device"
    if last_used(candidate) > cutoff:
        return "recent_directory"
    if candidate.marker is not None:
        if candidate.marker.is_symlink() or not candidate.marker.is_file() or candidate.marker.stat().st_mtime > cutoff:
            return "recent_or_invalid_marker"
    if not recognized_cache(candidate.cache_root or path):
        return "missing_cache_tag"
    if os.path.lexists(path / "Cargo.toml") or os.path.lexists(path / ".git"):
        return "source_present"
    if candidate.source is not None and os.path.lexists(candidate.source):
        return "temporary_source_exists"
    if any(mount == path or path in mount.parents for mount in mount_points()):
        return "nested_mount"
    recent = subprocess.run(
        ["find", str(path), "-xdev", "(", "-name", ".git", "-o", "-newermt", "@" + str(cutoff), ")", "-print", "-quit"],
        capture_output=True, text=True, timeout=120
    )
    if recent.returncode:
        raise RuntimeError("Cannot inspect target: " + str(path))
    if recent.stdout.strip():
        return "source_or_recent_contents"
    return None


@contextlib.contextmanager
def candidate_lock(path):
    if path is None:
        yield True
        return
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    except (FileNotFoundError, PermissionError, OSError):
        yield False
        return
    try:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            yield False
            return
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            yield False
            return
        yield True
    finally:
        os.close(descriptor)


def clean_candidates(candidates, device, cutoff, dry_run):
    counts = collections.Counter()
    skipped = collections.Counter()
    for candidate in candidates:
        with candidate_lock(candidate.lock) as acquired:
            if not acquired:
                skipped["locked_or_missing_lock"] += 1
                continue
            reason = guard_candidate(candidate, device, cutoff)
            if reason:
                skipped[reason] += 1
                continue
            previous = candidate.path.stat()
            references = inspect_processes()
            if any(token in reference for token in candidate.tokens for reference in references):
                skipped["active_reference"] += 1
                continue
            current = candidate.path.stat()
            fields = ("st_dev", "st_ino", "st_mtime_ns", "st_ctime_ns")
            if any(getattr(previous, field) != getattr(current, field) for field in fields):
                skipped["changed_during_inspection"] += 1
                continue
            reason = guard_candidate(candidate, device, cutoff)
            if reason:
                skipped[reason] += 1
                continue
            if not dry_run:
                subprocess.run(["rm", "-rf", "--one-file-system", "--", str(candidate.path)], check=True, timeout=300)
                if os.path.lexists(candidate.path):
                    raise RuntimeError("Target remains after cleanup: " + str(candidate.path))
            counts[candidate.kind] += 1
            emit("would_remove" if dry_run else "removed", kind=candidate.kind, path=str(candidate.path))
    return counts, skipped


def clean_budget(candidates, roots, device, max_bytes, dry_run, now):
    before = allocated_bytes(roots)
    age = 2 * 3600 if dry_run and before > max_bytes else 2 * 86400
    counts, skipped = clean_candidates(candidates, device, now - age, dry_run)
    if not dry_run:
        # The budget can evict idle builds after two hours. Running builds,
        # recent files and nested source checkouts remain protected.
        for candidate in candidates:
            if allocated_bytes(roots) <= max_bytes:
                break
            removed, reasons = clean_candidates([candidate], device, now - 2 * 3600, False)
            counts.update(removed)
            skipped.update(reasons)
    after = allocated_bytes(roots)
    emit("summary", dry_run=dry_run, removed=dict(counts) if not dry_run else {},
         eligible=dict(counts) if dry_run else {}, skipped=dict(skipped),
         cache_bytes_before=before, cache_bytes_after=after, cache_limit_bytes=max_bytes, over_budget=after > max_bytes)


def main():
    parser = argparse.ArgumentParser(description="Expire unused Bex build outputs within a shared cache budget")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--max-bytes", type=int, default=128 * 1024 ** 3)
    arguments = parser.parse_args()
    if arguments.max_bytes <= 0:
        parser.error("--max-bytes must be positive")
    home = pathlib.Path.home()
    store = home / ".cargo"
    remote = home / ".cache/agent-remote-builds"
    validate_mounts(store, remote)
    descriptor = os.open(remote / ".bex-cache-maintenance.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
    try:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise RuntimeError("Invalid maintenance lock")
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            emit("skipped", reason="maintenance_already_running")
            return
        candidates = collect_candidates(store, remote)
        roots = [store / "targets", *(candidate.path for candidate in candidates)]
        emit("start", dry_run=arguments.dry_run, minimum_age_days=2, candidate_count=len(candidates))
        clean_budget(candidates, roots, store.stat().st_dev, arguments.max_bytes, arguments.dry_run, time.time())
    finally:
        os.close(descriptor)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        emit("error", message=str(error))
        sys.exit(1)
