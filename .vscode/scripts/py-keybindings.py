#!/usr/bin/env python3
# Copyright 2025 RnD Center "ELVEES", JSC

# pylint: disable=bad-indentation
# pylint: disable=import-error
# pylint: disable=invalid-name
# pylint: disable=missing-class-docstring
# pylint: disable=missing-function-docstring
# pylint: disable=missing-module-docstring
# pylint: disable=too-few-public-methods
# pylint: disable=too-many-branches
# pylint: disable=too-many-instance-attributes
# pylint: disable=too-many-statements

import filecmp
import json
import os
import shutil
import sys

import jstyleson  # type: ignore # pip3 install jstyleson


def append_vscode_keybindings(bindings, modified, ignore_keys, new_binding):
    index = 0
    count = len(bindings)
    while index < count:
        binding = bindings[index]
        found = True
        for _, (key, value) in enumerate(new_binding.items()):
            if key in ignore_keys:
                continue
            found = key in binding and str(binding[key]) == value
            if not found:
                break
        if not found:
            index += 1
            continue
        if binding != new_binding:
            print(f"Updating keybinding: {new_binding}")
            bindings[index] = new_binding
            return bindings, True
        print(f"Keybinding already exists: {new_binding}")
        return bindings, modified
    print(f"Registering keybinding: {new_binding}")
    bindings.append(new_binding)
    return bindings, True


def compare_and_copy(source_file, dest_file):
    if not filecmp.cmp(source_file, dest_file):
        shutil.copy2(source_file, dest_file)
        print(f"Keybindings from '{source_file}' copied to '{dest_file}'")
    else:
        print("Keybindings already the same, no need to update.")


def modify_vscode_keybindings(path):
    bindings = []
    if os.path.exists(path) and os.path.isfile(path):
        print(f"Loading keybindings from '{path}'")
        with open(path, 'r', encoding='utf-8') as file:
            bindings = jstyleson.loads(file.read())
    modified = False
    bindings, modified = append_vscode_keybindings(bindings, modified, ["args"], {
        "key": "ctrl+b",
        "command": "workbench.action.tasks.runTask",
        "args": "Goflame: Build workspace"})
    bindings, modified = append_vscode_keybindings(bindings, modified, ["args"], {
        "key": "ctrl+shift+b",
        "command": "workbench.action.tasks.runTask",
        "args": "Goflame: Check&build workspace"})
    bindings, modified = append_vscode_keybindings(bindings, modified, ["when"], {
        "key": "f5",
        "command": "workbench.action.debug.start",
        "when": "debuggersAvailable && debugState == 'inactive'"})
    bindings, modified = append_vscode_keybindings(bindings, modified, ["when"], {
        "key": "f5",
        "command": "workbench.action.debug.continue",
        "when": "debugState == 'stopped'"})
    bindings, modified = append_vscode_keybindings(bindings, modified, ["when"], {
        "key": "f2",
        "command": "workbench.action.debug.stop",
        "when": "inDebugMode && !focusedSessionIsAttach"})
    if not modified:
        print("Keybindings already registered. Existing.")
        return
    print(f"Saving keybindings to '{path}'")
    temp_path = path + ".tmp"
    with open(temp_path, 'w', encoding='utf-8') as file:
        json.dump(bindings, file, ensure_ascii=False, indent=4)
        file.write("\n")
    compare_and_copy(temp_path, path)
    os.remove(temp_path)


def apply_vscode_keybindings():
    index = 1
    while index < len(sys.argv):
        modify_vscode_keybindings(sys.argv[index])
        index += 1


apply_vscode_keybindings()
