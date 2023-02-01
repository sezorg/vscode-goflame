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

# "me" for current git user, "" or "all'" for all users
gerrit_email="me"

# include patchets yes/no
gerrit_patchsets="no"

function debug() {
    #echo "dd debug: $*"
    return 0
}

nl=$'\n'
tag_prefix="T/"
tag_postfix=""
branch_prefix="B/"
branch_postfix=""

conf_email=""
conf_file="/var/tmp/gerrit-conf.txt"
git config --list > "${conf_file}"
conf_text=()
readarray -t conf_text < "${conf_file}"
debug "conf_text count:${#conf_text[@]}"
for conf_line in "${conf_text[@]}"; do 
    if [[ "${conf_line}" =~ ^"user.email="* ]]; then
        conf_email="${conf_line:11}"
    fi
done

echo "-- fetching & checkingout to master"
current_branch=$(git rev-parse --abbrev-ref HEAD)
restore_branch=""
git fetch --all --quiet
git checkout master --quiet

tags_file="/var/tmp/gerrit-tags.txt"
git tag > "${tags_file}"
tags_text=()
readarray -t tags_text < "${tags_file}"
debug "-- removing ${#tags_text[@]} tags"
for tags_line in "${tags_text[@]}"; do
    if [[ "${tags_line}" =~ ^"${tag_prefix}"[[:digit:]]+.*"${tag_postfix}"$ ]]; then
        git tag -d "${tags_line}" > /dev/null
    fi
done

branches_file="/var/tmp/gerrit-branches.txt"
git branch --format "%(refname:short)" > "${branches_file}"
branches_text=()
readarray -t branches_text < "${branches_file}"
debug "-- removing ${#branches_text[@]} branches"
for branches_line in "${branches_text[@]}"; do
    if [[ "${branches_line}" =~ ^"${branch_prefix}"[[:digit:]]+.*"${branch_postfix}"$ ]]; then
        git branch -D "${branches_line}" > /dev/null
    fi
done

set +u
if [ "${1}" != "" ]; then
    gerrit_email="${1}"
fi
set -u
if [[ "${gerrit_email}" == "del" ]]; then
    exit 0
elif [[ "${gerrit_email}" == "me" ]]; then
    gerrit_email="${conf_email}"
elif [[ "${gerrit_email}" == "all" ]] || [[ "${gerrit_email}" == "" ]]; then
    gerrit_email=""
elif [[ "${gerrit_email##*@}" == "${gerrit_email}" ]]; then
    gerrit_email="${gerrit_email}@${conf_email##*@}"
fi

changes_file="/var/tmp/gerrit-changes.txt"
git gerrit changes "${gerrit_filter}" > "${changes_file}"
changes_text=()
readarray -t changes_text < "${changes_file}"
debug "changes_text count:${#changes_text[@]}"

count="0"
mode=""
change_id=""
number=""
subject=""
email=""
username=""
url=""
patch_num=""
curr_num=""
revision=""
ref=""

for changes_line in "${changes_text[@]}"; do 
    if [[ "${changes_line}" =~ ^"change "* ]]; then
        change_id="${changes_line:7}"
        number=""
        subject=""
        email=""
        username=""
        url=""
        patch_num=""
        curr_num=""
        revision=""
        ref=""
        debug "change: \"${change_id}\""
        mode="change"
        debug "mode: \"${mode}\""
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
        if [[ "${changes_line}" =~ ^"    email: "* ]]; then
            email="${changes_line:11}"
            debug "email: \"${email}\""
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
            mode="currentPatchSet"
            debug "mode: \"${mode}\""
        fi
    fi

    if [[ "${mode}" == "currentPatchSet" ]] || [[ "${mode}" == "patchSets" ]]; then 
        if [[ "${changes_line}" =~ ^"    number: "* ]]; then
            patch_num="${changes_line:12}"
            if [[ "${mode}" == "currentPatchSet" ]]; then
                curr_num="${patch_num}"
            fi
            debug "patch_num: \"${patch_num}\" curr_num:\"${curr_num}\""

        fi
        if [[ "${changes_line}" =~ ^"    revision: "* ]]; then
            revision="${changes_line:14}"
            debug "revision: \"${revision}\""
        fi
        if [[ "${changes_line}" =~ ^"    ref: "* ]]; then
            ref="${changes_line:9}"
            debug "ref: \"${ref}\""
            mode="${mode}Add"
            debug "mode: \"${mode}\""
        fi
    fi

    if [[ "${mode}" == "listPatchSets" ]]; then 
        if [[ "${changes_line}" =~ ^"  patchSets:"$ ]]; then
            patch_num=""
            revision=""
            ref=""
            mode="patchSets"
            debug "mode: \"${mode}\""
        fi
    fi

    if [[ "${mode}" == "currentPatchSetAdd" ]] || [[ "${mode}" == "patchSetsAdd" ]]; then 
        if [[ "${change_id}" != "" ]] && \
            [[ "${number}" != "" ]] && \
            [[ "${subject}" != "" ]] && \
            [[ "${email}" != "" ]] && \
            [[ "${email}" != "" ]] && \
            [[ "${url}" != "" ]] && \
            [[ "${patch_num}" != "" ]] && \
            [[ "${curr_num}" != "" ]] && \
            [[ "${revision}" != "" ]] && \
            [[ "${ref}" != "" ]]; then

            if [[ "${mode}" == "currentPatchSetAdd" ]] || \
                [[ "${patch_num}" != "${curr_num}" ]]; then

                debug "gerrit_email: ${gerrit_email} email:${email}"
                if [[ "${gerrit_email}" == "" ]] || \
                    [[ "${gerrit_email}" == "${email}" ]]; then
                    entry_name="${number}"
                    if [[ "${gerrit_patchsets}" == "yes" ]]; then
                        entry_name="${entry_name}/${patch_num}"
                        if [[ "${mode}" == "currentPatchSetAdd" ]]; then
                            entry_name="${entry_name}/current"
                        fi
                    fi
                    if [[ "${gerrit_email}" == "" ]]; then
                        entry_name="${entry_name}-${username}"
                    fi
                    tag_name="${tag_prefix}${entry_name}${tag_postfix}"
                    branch_name="${branch_prefix}${entry_name}${branch_postfix}"

                    tag_mssg="${subject}${nl}Url:${url}${nl}Change-id: ${change_id}"
                    tag_mssg="${subject}"

                    git fetch origin "${ref}" > /dev/null 2>&1
                    #git checkout FETCH_HEAD
                    count=$((count+1))
                    count_str=$(printf "%02d" "${count}")
                    echo "${count_str} adding tag ${revision:0:8} ${tag_name}: ${subject}"
                    debug "git tag \"${tag_name}\" \"${revision}\" -m \"${tag_mssg}\""
                    git tag "${tag_name}" "${revision}" -m "${tag_mssg}" > /dev/null 2>&1
                    git branch "${branch_name}" "${tag_name}"

                    if [[ "${current_branch}" == "${branch_name}" ]]; then
                        restore_branch="${branch_name}"
                    fi
                fi
            fi
        fi

        if [[ "${gerrit_patchsets}" == "yes" ]]; then
            mode="listPatchSets"
            debug "mode: \"${mode}\""
        else
            mode=""
            debug "mode: \"${mode}\""
        fi
    fi
done

if [[ "${restore_branch}" != "" ]]; then
    echo "-- checkingout back to ${restore_branch}"
    git checkout "${restore_branch}" --quiet
fi
