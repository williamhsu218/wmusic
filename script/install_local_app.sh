#!/usr/bin/env bash
# Install the local candidate and retain exactly one verified rollback snapshot.
set -euo pipefail
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v python3 >/dev/null || { echo "Missing install tool: python3" >&2; exit 1; }
exec python3 - "$root_dir" "$@" <<'PY'
import datetime
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import shutil
import sqlite3
import stat
import subprocess
import sys
import tempfile
import time
import uuid

BUNDLE_ID = "com.willhsu.wmusic.local"
root = Path(sys.argv[1])
home = Path.home()
applications = Path("/Applications")
args = sys.argv[2:]
fixture_mode = bool(args)
if args:
    # No production path overrides: fixtures must be explicitly marked and live
    # directly inside a system temporary directory. Signing checks still run.
    if len(args) != 2 or args[0] != "--fixture-root":
        sys.exit("Usage: install_local_app.sh [--fixture-root TEMPORARY_TEST_DIRECTORY]")
    fixture = Path(args[1]).resolve()
    temp_parents = {Path(tempfile.gettempdir()).resolve(), Path("/tmp").resolve()}
    marker = fixture / ".wmusic-install-fixture"
    if (fixture.parent not in temp_parents
            or not fixture.name.startswith("wmusic-install-fixture.")
            or not marker.is_file() or marker.is_symlink()
            or marker.read_text() != "WMusic install fixture\n"):
        sys.exit("Fixture root must be a marked wmusic-install-fixture.* system temporary directory")
    root, home, applications = fixture, fixture, fixture / "Applications"

candidate = root / "dist/WMusic.app"
installed = applications / "WMusic.app"
backup_base = root / ".build-logs/install-backups"
rollback = backup_base / "current-rollback"
library = home / f"Library/Containers/{BUNDLE_ID}/Data/Library/Application Support/WMusic/library.sqlite"
if fixture_mode:
    for path in (candidate, applications, backup_base, library):
        resolved = path.resolve(strict=False)
        if fixture not in resolved.parents:
            sys.exit(f"Fixture path escapes its root: {path}")
    applications.mkdir(exist_ok=True)


def fail(message):
    raise RuntimeError(message)


def run(*command):
    result = subprocess.run(command, capture_output=True)
    if result.returncode:
        detail = result.stderr.decode(errors="replace").strip()
        fail(f"{' '.join(map(str, command))} failed: {detail}")
    return result.stdout


def require_quit():
    executable = installed / "Contents/MacOS/WMusic"
    # comm contains the executable path, without arguments. Never search args:
    # another tool's shell text can contain /Applications/WMusic.app verbatim.
    processes = run("ps", "-axww", "-o", "pid=,comm=").decode(errors="replace")
    for line in processes.splitlines():
        fields = line.strip().split(None, 1)
        if len(fields) != 2:
            continue
        pid, command = fields
        if command == str(executable) or (command.startswith("/") and Path(command).resolve() == executable.resolve()):
            fail(f"WMusic at {executable} is running (PID {pid}). Quit it normally, then retry.")
        if command == "WMusic":
            fail(f"WMusic process {pid} has an unresolved executable path; confirm it is not the installed app before retrying")


def regular_directory(path):
    if path.is_symlink() or not path.is_dir():
        fail(f"Expected a real directory: {path}")


def validate_app(path):
    regular_directory(path)
    with (path / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if (info.get("CFBundleIdentifier") != BUNDLE_ID
            or info.get("CFBundleExecutable") != "WMusic"
            or info.get("CFBundlePackageType") != "APPL"):
        fail(f"Unexpected app identity: {path}")
    for key in ("CFBundleShortVersionString", "CFBundleVersion"):
        if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", str(info.get(key, ""))):
            fail(f"Missing or unresolved numeric {key}: {path}")
    executable = path / "Contents/MacOS/WMusic"
    if not executable.is_file() or not os.access(executable, os.X_OK):
        fail(f"Missing executable: {executable}")
    run("codesign", "--verify", "--deep", "--strict", str(path))
    signature = subprocess.run(["codesign", "-dvv", str(path)], capture_output=True)
    details = signature.stderr.decode(errors="replace")
    if signature.returncode or f"Identifier={BUNDLE_ID}" not in details.splitlines() or "Signature=adhoc" not in details.splitlines():
        fail(f"Expected the local ad-hoc signature and identifier: {path}")
    entitlements = plistlib.loads(run("codesign", "-d", "--entitlements", ":-", str(path)))
    if entitlements.get("com.apple.security.app-sandbox") is not True:
        fail(f"App Sandbox is missing: {path}")
    if entitlements.get("com.apple.security.get-task-allow") is True:
        fail(f"The app has the Debug get-task-allow entitlement: {path}")
    return {key: info[key] for key in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion")}


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def manifest(path):
    # JSON names safely represent spaces, newlines and Unicode. Include the full
    # directory/link inventory and executable modes, not only the main binary.
    records = []
    entries = [path]
    for directory, dirs, files in os.walk(path, followlinks=False):
        entries.extend(Path(directory) / name for name in dirs + files)
    for entry in sorted(entries):
        attributes = entry.lstat()
        record = {"path": str(entry.relative_to(path)), "mode": stat.S_IMODE(attributes.st_mode)}
        if entry.is_symlink():
            record.update(kind="symlink", target=os.readlink(entry))
        elif entry.is_dir():
            record.update(kind="directory")
        elif entry.is_file():
            record.update(kind="file", size=attributes.st_size, sha256=sha256(entry))
        else:
            fail(f"Unsupported file type in app: {entry}")
        records.append(record)
    return records


def assert_manifest(path, expected):
    if manifest(path) != expected:
        fail(f"Full app file/hash readback differs: {path}")


def write_json(path, value):
    encoded = json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    path.write_text(encoded)
    if path.read_text() != encoded:
        fail(f"Metadata readback differs: {path}")


def backup_library(destination):
    if library.is_symlink():
        fail(f"Library database must not be a symlink: {library}")
    if not library.exists():
        return {"status": "absent-before-install"}
    if not library.is_file():
        fail(f"Library database is not a regular file: {library}")
    deadline = time.monotonic() + 60

    def progress(status, remaining, total):
        if time.monotonic() > deadline:
            fail("SQLite online backup exceeded 60 seconds")

    source = sqlite3.connect(library.as_uri() + "?mode=ro", uri=True, timeout=5)
    output = sqlite3.connect(destination)
    try:
        if source.execute("PRAGMA quick_check").fetchall() != [("ok",)]:
            fail("The current library failed SQLite quick_check")
        source.backup(output, pages=256, progress=progress, sleep=0.05)
        if output.execute("PRAGMA journal_mode=DELETE").fetchone() != ("delete",):
            fail("The offline library snapshot could not leave WAL mode")
        if output.execute("PRAGMA quick_check").fetchall() != [("ok",)]:
            fail("The library snapshot failed SQLite quick_check")
    finally:
        output.close()
        source.close()
    # SQLite's backup API includes committed WAL data and never replaces or
    # checkpoints the live database. Only this standalone snapshot is retained.
    return {"status": "backed-up", "sha256": sha256(destination), "quick_check": "ok", "journal_mode": "delete"}


def verify_snapshot(path, previous_files, database, metadata_hashes):
    if previous_files is not None:
        assert_manifest(path / "WMusic.app", previous_files)
    if database["status"] == "backed-up":
        snapshot = path / "library.sqlite"
        if sha256(snapshot) != database["sha256"]:
            fail(f"Library snapshot hash readback differs: {snapshot}")
        connection = sqlite3.connect(snapshot.as_uri() + "?mode=ro", uri=True)
        try:
            if connection.execute("PRAGMA journal_mode").fetchone() != ("delete",):
                fail(f"Library snapshot unexpectedly uses WAL mode: {snapshot}")
            if connection.execute("PRAGMA quick_check").fetchall() != [("ok",)]:
                fail(f"Library snapshot quick_check failed: {snapshot}")
        finally:
            connection.close()
    for name, expected in metadata_hashes.items():
        if sha256(path / name) != expected:
            fail(f"Rollback metadata hash readback differs: {path / name}")


def refresh_launch_services(icon_changed):
    if fixture_mode:
        return
    registration = Path("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")
    try:
        run(str(registration), "-f", str(installed))
        if icon_changed:
            os.utime(installed, None)
            result = subprocess.run(["killall", "Dock"], capture_output=True)
            if result.returncode not in (0, 1):
                fail(result.stderr.decode(errors="replace"))
    except Exception as error:
        print(f"App installed, but icon registration needs attention: {error}", file=sys.stderr)


def interrupted(signum, frame):
    fail(f"Install interrupted by signal {signum}")


@contextmanager
def rename_step():
    # A signal cannot observe a completed rename before its recovery flag is
    # updated. Deliver any pending interrupt immediately after both are done.
    old_mask = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGTERM, signal.SIGINT})
    try:
        yield
    finally:
        signal.pthread_sigmask(signal.SIG_SETMASK, old_mask)


signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)
class AlreadyCurrent(Exception):
    pass


lock = backup_base / ".install.lock"
stage = next_rollback = retired = None
previous_files = None
previous_moved = candidate_promoted = rollback_promoted = committed = False
keep_recovery = False
locked = False
try:
    for tool in ("codesign", "ditto", "ps"):
        if shutil.which(tool) is None:
            fail(f"Missing install tool: {tool}")
    require_quit()
    candidate_info = validate_app(candidate)
    candidate_files = manifest(candidate)
    regular_directory(applications)
    if not os.access(applications, os.W_OK):
        fail(f"Current user cannot write {applications}; no privileged install was attempted")
    for directory in (root / ".build-logs", backup_base):
        if directory.is_symlink():
            fail(f"Backup directory must not be a symlink: {directory}")
        directory.mkdir(exist_ok=True)
        regular_directory(directory)
    if rollback.exists() or rollback.is_symlink():
        regular_directory(rollback)
    try:
        lock.mkdir()
        locked = True
    except FileExistsError:
        fail(f"Another install or interrupted install owns {lock}; inspect it before retrying")
    (lock / "owner.txt").write_text(f"pid={os.getpid()}\n")
    if installed.exists() or installed.is_symlink():
        validate_app(installed)
        previous_files = manifest(installed)
        if previous_files == candidate_files:
            print(f"Already current: {installed}")
            print(f"Existing rollback preserved: {rollback}")
            raise AlreadyCurrent()
    icon = Path("Contents/Resources/AppIcon.icns")
    previous_icon = sha256(installed / icon) if (installed / icon).is_file() else None
    candidate_icon = sha256(candidate / icon) if (candidate / icon).is_file() else None
    stage = Path(tempfile.mkdtemp(prefix=".wmusic-install.", dir=applications))
    next_rollback = Path(tempfile.mkdtemp(prefix=".rollback-next.", dir=backup_base))
    stage_app = stage / "WMusic.app"
    moved_app = stage / "previous-installed.app"
    run("ditto", str(candidate), str(stage_app))
    validate_app(stage_app)
    assert_manifest(stage_app, candidate_files)
    if previous_files is not None:
        run("ditto", str(installed), str(next_rollback / "WMusic.app"))
        assert_manifest(next_rollback / "WMusic.app", previous_files)
    database = backup_library(next_rollback / "library.sqlite")
    metadata = {
        "created_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "installed_app": str(installed), "installed_version": candidate_info,
        "previous_app_present": previous_files is not None, "database": database,
    }
    write_json(next_rollback / "installation.json", metadata)
    write_json(next_rollback / "installed-app-files.json", candidate_files)
    write_json(next_rollback / "previous-app-files.json", previous_files)
    metadata_hashes = {path.name: sha256(path) for path in next_rollback.glob("*.json")}
    verify_snapshot(next_rollback, previous_files, database, metadata_hashes)
    require_quit()
    assert_manifest(candidate, candidate_files)
    if previous_files is not None:
        assert_manifest(installed, previous_files)
        with rename_step():
            installed.rename(moved_app)
            previous_moved = True
    with rename_step():
        stage_app.rename(installed)
        candidate_promoted = True
    validate_app(installed)
    assert_manifest(installed, candidate_files)
    assert_manifest(candidate, candidate_files)
    if rollback.exists():
        retired = backup_base / f".rollback-retired.{uuid.uuid4().hex}"
        with rename_step():
            rollback.rename(retired)
    with rename_step():
        next_rollback.rename(rollback)
        rollback_promoted = True
    verify_snapshot(rollback, previous_files, database, metadata_hashes)
    committed = True
    if retired is not None:
        shutil.rmtree(retired)
    shutil.rmtree(stage)
    refresh_launch_services(previous_icon != candidate_icon)
    print(f"Installed: {installed}")
    print(f"Version: {candidate_info['CFBundleShortVersionString']} ({candidate_info['CFBundleVersion']})")
    print(f"Single rollback: {rollback}")
    print("Full app hashes, signatures and SQLite snapshot readback passed. The app was not launched.")
except AlreadyCurrent:
    pass
except BaseException as error:
    # Once recovery begins, finish the short rename sequence without another
    # interrupt deleting the only usable copy. SIGKILL leaves the lock and stages.
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    print(f"Install failed: {error}", file=sys.stderr)
    if not committed:
        try:
            if rollback_promoted:
                rollback.rename(next_rollback)
            if retired is not None and retired.exists():
                retired.rename(rollback)
            if candidate_promoted or previous_moved:
                require_quit()
                if candidate_promoted:
                    installed.rename(stage / "failed-candidate.app")
                if previous_moved:
                    moved_app.rename(installed)
                    assert_manifest(installed, previous_files)
                print("Previous installed app restored; live library was not replaced.", file=sys.stderr)
        except Exception as recovery_error:
            keep_recovery = True
            print(f"Automatic recovery could not complete: {recovery_error}", file=sys.stderr)
    else:
        keep_recovery = True
        print("The verified new app and rollback are installed, but cleanup needs attention.", file=sys.stderr)
    if keep_recovery:
        print(f"Preserved recovery paths: {stage}, {next_rollback}, {retired}", file=sys.stderr)
    sys.exit(1)
finally:
    if not keep_recovery:
        for path in (stage, next_rollback):
            if path is not None and path.exists():
                shutil.rmtree(path)
    if locked and not keep_recovery:
        shutil.rmtree(lock)
PY
