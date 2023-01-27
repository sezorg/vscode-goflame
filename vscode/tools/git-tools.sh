#!/bin/bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# Git-Gerrit tags
# Requires:
#   https://github.com/fbzhong/git-gerrit

#set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

function gh() {
    echo "gr: git rebase -i HEAD~\${1}"
    echo "gc: git rebase --continue"
    echo "gs: git status"
    echo "ga: git add -u"
    echo "gp: git push origin HEAD:refs/for/master"
    echo "gt: gerrit-tags [me/all/username/user@mail]"
    return 0
}

function gr() {
    git rebase -i "HEAD~${1}"
}

function gc() {
    git rebase --continue
}

function gs() {
    git status
}

function ga() {
    git add -u
}

function gp() {
    git push origin HEAD:refs/for/master
}

function gt() {
    "gerrit-tags.sh" "${1}"
}

