#!/bin/bash
# Changelog and SettingsTransfer (iOSClient/Changelog.swift, iOSClient/SettingsTransfer.swift) on their own.
#   Tests/checks/changelog/run.sh             compile and run the check
#   Tests/checks/changelog/run.sh --mutants   one-line mutants of both files; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/Changelog.swift iOSClient/SettingsTransfer.swift "$here/main.swift" -o "$out/check"
"$out/check" "$root/iOSClient/Sill.xcodeproj/project.pbxproj"
