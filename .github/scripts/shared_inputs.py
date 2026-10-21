"""Whether a change to the shared build inputs reaches the apps.

`mise.toml` and `project.yml` are each read by both apps' jobs, so a change to one says nothing on its own about which
it can break. This prints `apple=` and `android=` (`true|false`) for the change between two commits:

- mise.toml: a tool that platform's jobs install (`just`, `uv` and `xcodegen` for Apple, `cargo-ndk` for Android), or
  anything outside [tools], which mise exports to every job that installs from it. The Core job does not use mise.
- project.yml: the Android build reads MARKETING_VERSION from it and nothing else. The iOS project is generated from
  the whole file, so its path list counts every change.

`Cargo.lock` needs no such question: both workspace members are in every domain that builds Rust (groglog-core links
uniffi, whose dependencies are most of the lock). No job runs a justfile recipe, so the justfile reaches none of them.

    python3 shared_inputs.py BASE HEAD
"""

import re
import subprocess
import sys
import tomllib

APPLE_TOOLS = {"just", "uv", "xcodegen"}
ANDROID_TOOLS = {"cargo:cargo-ndk"}


def show(rev, path):
    out = subprocess.run(["git", "show", f"{rev}:{path}"], capture_output=True, text=True)
    return out.stdout if out.returncode == 0 else ""


def mise_reaches(old, new, tools):
    before = tomllib.loads(old) if old else {}
    after = tomllib.loads(new) if new else {}
    tools_before, tools_after = before.pop("tools", {}), after.pop("tools", {})
    if before != after:
        return True
    return any(tools_before.get(t) != tools_after.get(t) for t in tools)


def marketing_version(text):
    return re.findall(r"MARKETING_VERSION: *(\S+)", text)


def main():
    base, head = sys.argv[1:3]
    mise_old, mise_new = show(base, "mise.toml"), show(head, "mise.toml")
    apple = mise_reaches(mise_old, mise_new, APPLE_TOOLS)
    android = mise_reaches(mise_old, mise_new, ANDROID_TOOLS) or marketing_version(
        show(base, "project.yml")
    ) != marketing_version(show(head, "project.yml"))
    print(f"apple={str(apple).lower()}")
    print(f"android={str(android).lower()}")


main()
