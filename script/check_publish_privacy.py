#!/usr/bin/env python3
"""Reject personal network addresses in NAS code and publication documents."""

import argparse
import ipaddress
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IPV4 = re.compile(rb"(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?![\w.])")
IPV6 = re.compile(rb"\[([0-9a-fA-F:]+)(?:%[0-9a-zA-Z]+)?\]")
TEST_NETWORKS = tuple(map(ipaddress.ip_network, (
    "192.0.2.0/24", "198.51.100.0/24", "203.0.113.0/24", "2001:db8::/32",
)))


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args])


def in_scope(path):
    return (
        path in {"README.md", "VALIDATION.md", "AGENTS.md"}
        or path.startswith("docs/")
        or path.endswith("Localizable.xcstrings")
        or any(part in path for part in ("NAS", "NetworkShare", "NetworkFolder"))
    )


def violations(path, data):
    found = IPV4.findall(data) + IPV6.findall(data)
    for value in found:
        try:
            address = ipaddress.ip_address(value.decode("ascii"))
        except ValueError:
            continue
        if "/Tests/" in path:
            if address.is_link_local and address.version == 6:
                continue
            if any(address in network for network in TEST_NETWORKS
                   if address.version == network.version):
                continue
        yield address


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--history", action="store_true",
                        help="Check every commit reachable from local branches and tags")
    args = parser.parse_args()
    failures = set()
    checked = set()
    paths = git("ls-files", "-z").decode().split("\0")
    for path in filter(in_scope, filter(None, paths)):
        if list(violations(path, (ROOT / path).read_bytes())):
            failures.add(("working tree", path))
        checked.add(path)
    if args.history:
        seen = set()
        for commit in git("rev-list", "--all").decode().splitlines():
            for entry in git("ls-tree", "-r", "-z", commit).split(b"\0"):
                if not entry:
                    continue
                info, name = entry.split(b"\t", 1)
                _, kind, oid = info.split()
                path = name.decode()
                if kind != b"blob" or not in_scope(path) or (path, oid) in seen:
                    continue
                seen.add((path, oid))
                if list(violations(path, git("cat-file", "blob", oid.decode()))):
                    failures.add((commit[:12], path))
                checked.add(path)
    for revision, path in sorted(failures):
        # Never echo the address that caused a failure.
        print(f"FAIL {revision}: {path} contains a network address")
    print(f"Checked {len(checked)} NAS/publication files; {len(failures)} violations")
    return bool(failures)


if __name__ == "__main__":
    raise SystemExit(main())
