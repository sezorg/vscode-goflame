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

nl=$'\n'
tag_prefix="T/"
tag_postfix=""
branch_prefix="B/"
branch_postfix=""

red=$(printf "\e[31m")
green=$(printf "\e[32m")
yellow=$(printf "\e[33m")
blue=$(printf "\e[34m")
gray=$(printf "\e[90m")
nc=$(printf "\e[0m")
cregexp="s/\x1B\[([0-9]{1,3}(;[0-9]{1,3})*)?[mGK]//g"

function debug() {
    #echo "${green}debug:$nc ${*}"
    return 0
}

conf_email=""
conf_file="/var/tmp/gerrit-conf.txt"
git prune
git config --list > "$conf_file"
conf_text=()
readarray -t conf_text < "$conf_file"
debug "conf_text count:${#conf_text[@]}"
for conf_line in "${conf_text[@]}"; do
    if [[ "$conf_line" =~ ^"user.email="* ]]; then
        conf_email="${conf_line:11}"
    fi
done

message_width="65"
message_ruler=""

count="0"
while [[ "$count" -lt "$message_width" ]]; do
    digit=$((count % 10))
    count=$((count + 1))
    message_ruler="$message_ruler$(printf "%d" "$digit")"
done

message_head_prefix="$gray--$nc ---------- $green--sha1-- $blue--tag--$nc $message_ruler"

message_head_size=$(echo "$message_head_prefix" | sed -r "$cregexp")
message_head_size="${#message_head_size}"
table_line_xfill=""
table_line_blank=""
count="0"
while [[ "$count" -lt "$message_head_size" ]]; do
    count=$((count + 1))
    table_line_xfill="$table_line_xfill-"
    table_line_blank="$table_line_blank "
done

message_head="$message_head_prefix -"
table_line_xfill="$table_line_xfill--"
table_line_blank="$table_line_blank -"

function mssg() {
    plain=$(echo "$1" | sed -r "$cregexp")
    echo "$1${table_line_blank:${#plain}}"
}

function mssg_fill() {
    plain=$(echo "$1" | sed -r "$cregexp")
    echo "$1${table_line_xfill:${#plain}}"
}

function mssg_head() {
    mssg "$message_head"
}

if ! which "git-gerrit" &> /dev/null; then
    echo "${red}ERROR:$nc Seems to be there is no ${blue}git-gerrit$nc installed."
    echo "${red}ERROR:$nc Installation instructions can be found at:"
    echo "${red}ERROR:$nc     ${yellow}https://github.com/fbzhong/git-gerrit$nc"
    exit 1
fi

current_revision=$(git rev-parse HEAD)
current_branch=$(git rev-parse --abbrev-ref HEAD)
restore_branch=""
restore_message=""
mssg_fill "$gray--$nc fetch and pull from $blue${current_branch}$nc to ${blue}origin/master$nc "
git fetch --all --quiet
git checkout master --quiet

tags_file="/var/tmp/gerrit-tags.txt"
git tag > "$tags_file"
tags_text=()
readarray -t tags_text < "$tags_file"
debug "removing ${#tags_text[@]} tags"
for tags_line in "${tags_text[@]}"; do
    if [[ "$tags_line" =~ ^"$tag_prefix"[[:digit:]]+.*"$tag_postfix"$ ]]; then
        git tag -d "$tags_line" > /dev/null
    fi
done

branches_file="/var/tmp/gerrit-branches.txt"
git branch --format "%(refname:short)" > "$branches_file"
branches_text=()
readarray -t branches_text < "$branches_file"
debug "removing ${#branches_text[@]} branches"
for branches_line in "${branches_text[@]}"; do
    if [[ "$branches_line" =~ ^"$branch_prefix"[[:digit:]]+.*"$branch_postfix"$ ]]; then
        git branch -D "$branches_line" > /dev/null
    fi
done

set +u
if [[ "$1" != "" ]]; then
    gerrit_email="$1"
fi
set -u
if [[ "$gerrit_email" == "del" ]]; then
    exit 0
elif [[ "$gerrit_email" == "me" ]]; then
    gerrit_email="$conf_email"
elif [[ "$gerrit_email" == "all" ]] || [[ "$gerrit_email" == "" ]]; then
    gerrit_email=""
elif [[ "${gerrit_email##*@}" == "$gerrit_email" ]]; then
    gerrit_email="$gerrit_email@${conf_email##*@}"
fi

gerrit_email_filter=""
if [[ "$gerrit_email" != "" ]]; then
    gerrit_email_filter="author:'$gerrit_email'"
fi


changes_file="/var/tmp/gerrit-changes.txt"
debug "run: git gerrit changes \"$gerrit_filter $gerrit_email_filter\" > \"$changes_file\""
git gerrit changes "$gerrit_filter $gerrit_email_filter" > "$changes_file"
changes_text=()
readarray -t changes_text < "$changes_file"
debug "changes_text count:${#changes_text[@]}"

count="0"
mode=""
change_id=""
number=""
subject=""
email=""
username=""
url=""
wip=""
patch_num=""
curr_num=""
revision=""
ref=""
header_emit=""

for changes_line in "${changes_text[@]}"; do
    if [[ "$changes_line" =~ ^"change "* ]]; then
        change_id="${changes_line:7}"
        number=""
        subject=""
        email=""
        username=""
        url=""
        wip=""
        patch_num=""
        curr_num=""
        revision=""
        ref=""
        debug "change: \"$change_id\""
        mode="change"
        debug "mode: \"$mode\""
    fi

    if [[ "$mode" == "change" ]]; then
        if [[ "$changes_line" =~ ^"  number: "* ]]; then
            number="${changes_line:10}"
            debug "number: \"$number\""
        fi
        if [[ "$changes_line" =~ ^"  subject: "* ]]; then
            subject="${changes_line:11}"
            debug "subject: \"$subject\""
        fi
        if [[ "$changes_line" =~ ^"    email: "* ]]; then
            email="${changes_line:11}"
            debug "email: \"$email\""
        fi
        if [[ "$changes_line" =~ ^"    username: "* ]]; then
            username="${changes_line:14}"
            debug "username: \"$username\""
        fi
        if [[ "$changes_line" =~ ^"  url: "* ]]; then
            url="${changes_line:7}"
            debug "url: \"$url\""
        fi
        if [[ "$changes_line" =~ ^"  wip: "* ]]; then
            wip="${changes_line:7}"
            debug "wip: \"$wip\""
        fi
        if [[ "$changes_line" =~ ^"  currentPatchSet:"* ]]; then
            mode="currentPatchSet"
            debug "mode: \"$mode\""
        fi
    fi

    if [[ "$mode" == "currentPatchSet" ]] || [[ "$mode" == "patchSets" ]]; then
        if [[ "$changes_line" =~ ^"    number: "* ]]; then
            patch_num="${changes_line:12}"
            if [[ "$mode" == "currentPatchSet" ]]; then
                curr_num="$patch_num"
            fi
            debug "patch_num: \"$patch_num\" curr_num:\"$curr_num\""

        fi
        if [[ "$changes_line" =~ ^"    revision: "* ]]; then
            revision="${changes_line:14}"
            debug "revision: \"$revision\""
        fi
        if [[ "$changes_line" =~ ^"    ref: "* ]]; then
            ref="${changes_line:9}"
            debug "ref: \"$ref\""
            mode="${mode}Add"
            debug "mode: \"$mode\""
        fi
    fi

    if [[ "$mode" == "listPatchSets" ]]; then
        if [[ "$changes_line" =~ ^"  patchSets:"$ ]]; then
            patch_num=""
            revision=""
            ref=""
            mode="patchSets"
            debug "mode: \"$mode\""
        fi
    fi

    if [[ "$mode" == "currentPatchSetAdd" ]] || [[ "$mode" == "patchSetsAdd" ]]; then
        if [[ "$change_id" != "" ]] && \
            [[ "$number" != "" ]] && \
            [[ "$subject" != "" ]] && \
            [[ "$email" != "" ]] && \
            [[ "$email" != "" ]] && \
            [[ "$url" != "" ]] && \
            [[ "$patch_num" != "" ]] && \
            [[ "$curr_num" != "" ]] && \
            [[ "$revision" != "" ]] && \
            [[ "$ref" != "" ]]; then

            if [[ "$mode" == "currentPatchSetAdd" ]] || \
                [[ "$patch_num" != "$curr_num" ]]; then

                debug "gerrit_email: $gerrit_email email:$email"
                if [[ "$gerrit_email" == "" ]] || \
                    [[ "$gerrit_email" == "$email" ]]; then
                    entry_name="$number"
                    if [[ "$gerrit_patchsets" == "yes" ]]; then
                        entry_name="$entry_name/$patch_num"
                        if [[ "$mode" == "currentPatchSetAdd" ]]; then
                            entry_name="$entry_name/current"
                        fi
                    fi
                    if [[ "$gerrit_email" == "" ]]; then
                        entry_name="$entry_name-$username"
                    fi
                    tag_name="$tag_prefix${entry_name}$tag_postfix"
                    branch_name="$branch_prefix${entry_name}$branch_postfix"

                    tag_mssg="$subject${nl}Url:$url${nl}Change-id: $change_id"
                    tag_mssg="$subject"

                    git fetch origin "$ref" > /dev/null 2>&1
                    #git checkout FETCH_HEAD
                    count=$((count+1))
                    count_str=$(printf "%02d" "$count")
                    if [[ "$header_emit" == "" ]]; then
                        header_emit="1"
                        mssg_head
                    fi
                    subject_text="$subject"
                    subject_size="${#subject}"
                    subject_wip=""
                    subject_lim=""
                    subject_color=""
                    if [[ "$wip" == "true" ]]; then
                        subject_color="$yellow"
                        subject_wip=" [WIP]"
                    fi
                    if [[ "$subject_size" -gt "$message_width" ]]; then
                        subject_lim=" ($subject_size/$message_width)"
                        subject_color="$red"

                    fi
                    subject_text="$subject_color${subject_text}$nc${subject_wip}$subject_lim"
                    mssg "$gray${count_str}$nc adding tag $green${revision:0:8} $blue${tag_name}$nc $subject_text "
                    debug "git tag \"$tag_name\" \"$revision\" -m \"$tag_mssg\""
                    git tag "$tag_name" "$revision" -m "$tag_mssg" > /dev/null 2>&1
                    git branch "$branch_name" "$tag_name"

                    if [[ "$current_branch" == "$branch_name" ]] || \
                        [[ "$current_revision" == "$revision" ]]; then
                        restore_branch="$branch_name"
                        restore_message="$subject_text"
                    fi
                fi
            fi
        fi

        if [[ "$gerrit_patchsets" == "yes" ]]; then
            mode="listPatchSets"
            debug "mode: \"$mode\""
        else
            mode=""
            debug "mode: \"$mode\""
        fi
    fi
done

if [[ "$restore_branch" != "" ]]; then
    mssg_head
    mssg_fill "$gray--$nc checkout to restore $blue${restore_branch}$nc $restore_message "
    git checkout "$restore_branch" --quiet
fi
