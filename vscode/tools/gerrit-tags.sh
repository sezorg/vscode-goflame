#!/bin/bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# Git-Gerrit tags
# Requires:
#   https://github.com/fbzhong/git-gerrit

set -euo pipefail

# Serach filters described in:
# https://gerrit-review.googlesource.com/Documentation/user-search.html
gerrit_filter="status:open"
gerrit_owner="" #rabramov"

function debug() {
    #echo "debug: $*"
    return 0
}

nl=$'\n'
prefix="G-"

tags_file="/var/tmp/gerrit-tags.txt"
git fetch --all
git tag > "${tags_file}"
tags_text=()
readarray -t tags_text < "${tags_file}"
debug "tags_text count:${#tags_text[@]}"
for tags_line in "${tags_text[@]}"; do 
    if [[ "${tags_line}" =~ ^"${prefix}"* ]]; then
        git tag -d "${tags_line}" > /dev/null
    fi
done

changes_file="/var/tmp/gerrit-changes.txt"
git gerrit changes "${gerrit_filter}" > "${changes_file}"
changes_text=()
readarray -t changes_text < "${changes_file}"
debug "changes_text count:${#changes_text[@]}"

mode=""
change_id=""
number=""
subject=""
username=""
url=""
patch_set=""
revision=""
ref=""
for changes_line in "${changes_text[@]}"; do 
    if [[ "${changes_line}" =~ ^"change "* ]]; then
        mode="change"
        change_id="${changes_line:7}"
        number=""
        subject=""
        username=""
        url=""
        patch_set=""
        revision=""
        ref=""
        debug "change: \"${change_id}\""
    fi

    if [[ "${mode}" == "change" ]]; then 
        if [[ "${changes_line}" =~ ^"  number: "* ]]; then
            number="${changes_line:10}"
            debug "number: \"${number}\""
        fi
        if [[ "${changes_line}" =~ ^"  subject: "* ]]; then
            subject="${changes_line:11}"
            debug "subject: \"${subject}\""
        fi
        if [[ "${changes_line}" =~ ^"    username: "* ]]; then
            username="${changes_line:14}"
            debug "username: \"${username}\""
        fi
        if [[ "${changes_line}" =~ ^"  url: "* ]]; then
            url="${changes_line:14}"
            debug "url: \"${url}\""
        fi
        if [[ "${changes_line}" =~ ^"  currentPatchSet:"* ]]; then
            debug "currentPatchSet"
            mode="currentPatchSet"
        fi
    fi
    if [[ "${mode}" == "currentPatchSet" ]]; then 
        if [[ "${changes_line}" =~ ^"    number: "* ]]; then
            patch_set="${changes_line:12}"
            debug "patch_set: \"${patch_set}\""

        fi
        if [[ "${changes_line}" =~ ^"    revision: "* ]]; then
            revision="${changes_line:14}"
            debug "revision: \"${revision}\""
        fi
        if [[ "${changes_line}" =~ ^"    ref: "* ]]; then
            ref="${changes_line:9}"
            debug "ref: \"${ref}\""
            mode="addCurrentPatchSet"
        fi
    fi

    if [[ "${mode}" == "addCurrentPatchSet" ]]; then 
        mode=""
        if [[ "${change_id}" != "" ]] && \
            [[ "${number}" != "" ]] && \
            [[ "${subject}" != "" ]] && \
            [[ "${username}" != "" ]] && \
            [[ "${url}" != "" ]] && \
            [[ "${patch_set}" != "" ]] && \
            [[ "${revision}" != "" ]] && \
            [[ "${ref}" != "" ]]; then

            if [[ "${gerrit_owner}" == "" ]] || \
                [[ "${gerrit_owner}" == "${username}" ]]; then
                #echo "Change id:${change_id} num:${number} sub:\"${subject}\" url:${url} rev:${revision}"

                tag_name="${prefix}${number}"
                if [[ "${gerrit_owner}" == "" ]]; then
                    tag_name="${tag_name}-${username}"
                fi
                tag_mssg="${subject}${nl}Url:${url}${nl}Change-id: ${change_id}"
                tag_mssg="${subject}"

                git fetch origin "${ref}" > /dev/null 2>&1
                #git checkout FETCH_HEAD
                debug "adding tag ${tag_name} to ${revision}"
                debug "git tag \"${tag_name}\" \"${revision}\" -m \"${tag_mssg}\""
                git tag "${tag_name}" "${revision}" -m "${tag_mssg}" > /dev/null 2>&1
            fi
        fi
    fi
done

