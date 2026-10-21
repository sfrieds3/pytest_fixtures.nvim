#!/usr/bin/env python3
"""Tag the validated main commit; run only from the gated release job."""
import re
import subprocess
import sys


def git(*args):
    return subprocess.check_output(["git", *args], text=True).strip()


def main(commit):
    # Fetch tags explicitly, including when checkout has shallow history.
    git("fetch", "origin", "+refs/heads/main:refs/remotes/origin/main", "--tags")
    commit = git("rev-parse", "--verify", f"{commit}^{{commit}}")
    if git("rev-parse", "origin/main") != commit:
        print("Skipping superseded main commit")
        return
    versions = []
    for tag in git("tag", "--list").splitlines():
        match = re.fullmatch(r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", tag)
        if match:
            if git("rev-parse", f"{tag}^{{commit}}") == commit:
                print(f"Already released as {tag}")
                return
            versions.append(tuple(map(int, match.groups())))
    if versions:
        major, minor, patch = max(versions)
        tag = f"v{major}.{minor}.{patch + 1}"
    else:
        tag = "v0.1.0"
    git("tag", tag, commit)
    # Conflicts fail instead of moving or overwriting a remote tag.
    git("push", "origin", f"refs/tags/{tag}")
    print(f"Released {tag} at {commit}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: tag_version.py VALIDATED_COMMIT")
    main(sys.argv[1])
