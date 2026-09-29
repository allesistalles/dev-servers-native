#!/usr/bin/env python3
"""Validate release inputs and write bundle metadata without editing the source plist."""
import os
from pathlib import Path
import plistlib
import re
import sys


def configure(info, env):
    for key in ("SUFeedURL", "SUPublicEDKey", "SUEnableAutomaticChecks", "SUAutomaticallyUpdate", "SUVerifyUpdateBeforeExtraction", "SURequireSignedFeed"):
        info.pop(key, None)
    for variable, plist_key in [("WTP_VERSION", "CFBundleShortVersionString"), ("WTP_BUILD", "CFBundleVersion")]:
        value = env.get(variable, "")
        if value:
            if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", value):
                raise ValueError(f"{variable} must contain only numeric version components")
            info[plist_key] = value
    return info


def main():
    source, destination = map(Path, sys.argv[1:])
    try:
        info = configure(plistlib.loads(source.read_bytes()), os.environ)
    except ValueError as error:
        sys.exit(str(error))
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(plistlib.dumps(info, sort_keys=False))


if __name__ == "__main__":
    main()
