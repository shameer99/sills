#!/bin/bash
# StreamLayout (iOSClient/PhonePortraitLayout.swift, with iOSClient/DuoPosture.swift) on its own:
# one unified pure layout across every orientation, device size, fold and keyboard height.
#   Tests/checks/phone-portrait/run.sh             compile and run the check
#   Tests/checks/phone-portrait/run.sh --mutants   one-line mutants of PhonePortraitLayout.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/DuoPosture.swift iOSClient/PhonePortraitLayout.swift "$here/main.swift" -o "$out/check"
"$out/check"
