"""Mutants of TextFocusRule.swift, TextFocus.swift and StreamMessage.swift (kind 48): each changes
one line and must make Tests/checks/text-focus/main.swift fail. usage: mutants.py WORKTREE"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import module

RULE = "Sources/SillHost/TextFocusRule.swift"
WIRE = "Sources/StreamProtocol/TextFocus.swift"
MSG = "Sources/StreamProtocol/StreamMessage.swift"

MUTANTS = [
    # Classification
    ("disabled element treated as editable", RULE,
     "        if element.enabled == false { return TextFocus(editable: false) }\n", ""),
    ("AXEditable=false ignored", RULE,
     "        if element.editableAttribute == false { return TextFocus(editable: false) }\n", ""),
    ("AXTextArea left out of textRoles", RULE, '        "AXTextArea",\n', ""),
    ("AXComboBox left out of textRoles", RULE, '        "AXComboBox",\n', ""),
    ("AXSearchField left out of textRoles", RULE, '        "AXSearchField",\n', ""),
    ("read-only text field treated as editable", RULE,
     "            editable = element.valueSettable != false\n", "            editable = true\n"),
    ("AXSecureTextField not marked secure", RULE,
     "        let secure = element.subrole == secureSubrole\n", "        let secure = false\n"),
    ("AXEditable=true web content ignored", RULE,
     "        if element.editableAttribute == true {\n            editable = true\n        } else ", "        "),
    ("non-text control with settable value treated as editable", RULE,
     "        } else if element.role == webAreaRole && element.valueSettable == true {",
     "        } else if element.valueSettable == true {"),
    ("needsValueSettable always true", RULE,
     "        return subrole == secureSubrole || subrole == searchSubrole\n", "        return true\n"),
    # Tracker / debounce
    ("returning to current does not cancel pending", RULE,
     "            if focus == current {\n                pending = nil\n                return nil\n            }\n", ""),
    ("repeated pending starves debounce", RULE,
     "            if let existing = pending, existing.focus == focus, now >= existing.since {\n                return existing.since + Self.debounce\n            }\n", ""),
    ("flushes before debounce elapsed", RULE,
     "            guard now < pending.since || now - pending.since >= Self.debounce else { return nil }\n", ""),
    ("clock step back blocks flush", RULE,
     "now < pending.since || now - pending.since >= Self.debounce",
     "now - pending.since >= Self.debounce"),
    ("reset leaves current set", RULE, "            current = nil\n            pending = nil\n", "            pending = nil\n"),
    # Wire & kind
    ("isSecure ignores editable", WIRE, "public var isSecure: Bool { isEditable && secure == true }", "public var isSecure: Bool { secure == true }"),
    ("kind 48 numbered 250", MSG, "    case textFocus = 48 ", "    case textFocus = 250 "),
]

sys.exit(0 if module.mutate("text-focus", MUTANTS, sys.argv[1]) else 1)
