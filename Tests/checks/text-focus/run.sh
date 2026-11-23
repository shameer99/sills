#!/bin/bash
# TextFocusRule (Sources/SillHost/TextFocusRule.swift) and kind 48 TextFocus
# (Sources/StreamProtocol/TextFocus.swift): Accessibility editable focus classification (text roles,
# secure/search subroles, editable web content, disabled/read-only/non-text elements), debounced
# transition tracking, and wire encode/decode including WindowList.textFocus and older-client skip.
#   Tests/checks/text-focus/run.sh             compile and run the check
#   Tests/checks/text-focus/run.sh --mutants   one-line mutants; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
python3 "$here/../module.py" "$name" "$root" "$out/check"
