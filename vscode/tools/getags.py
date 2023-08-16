#!/usr/bin/env python3

#
# Create local named branches for Gerrit commints/changs.
#
# Usage:
# script [-p] [command]
#
# Where:
# -p			include PatchSets
#
# Command
# all			get tags for all users
# username	get tags for specified user
# me			all for me
# del			remove created branches

# pylint: disable=missing-module-docstring
# pylint: disable=missing-class-docstring
# pylint: disable=missing-function-docstring
# pylint: disable=bad-indentation
# pylint: disable=too-few-public-methods
# pylint: disable=too-many-branches
# pylint: disable=too-many-statements
# pylint: disable=too-many-instance-attributes

import argparse
import os
import re
import subprocess
import sys


class Config:
    debugLevel = 0
    verboseLevel = 0
    rebaseChains = False
    unprotectGit = True


class Colors:
    red = '\033[31m'
    green = '\033[32m'
    yellow = '\033[33m'
    blue = '\033[34m'
    gray = '\033[90m'
    nc = '\033[0m'
    cregexp = r's/\033\[([0-9]{1,3}(;[0-9]{1,3})*)?[mGK]//g'
    header = '\033[95m'
# blue = '\033[94m'
    cyan = '\033[96m'
    # green = '\033[92m'
    warning = '\033[93m'
    fail = '\033[91m'
    endc = '\033[0m'
    bold = '\033[1m'
    under = '\033[4m'


def debug(message):
    if Config.debugLevel > 0:
        print(f'DEBUG: {message}')


def verbose(message):
    if Config.verboseLevel > 0:
        print(f'VERBOSE: {message}')


def warning(message):
    print(f'{Colors.yellow}WARNING: {message}{Colors.nc}')


def error(message):
    print(f'{Colors.red}ERROR: {message}{Colors.nc}')


def fatal(message):
    print(f'{Colors.red}FATAL: {message}{Colors.nc}')
    sys.exit()


def remove_from_dict(dictionary, values):
    for value in values:
        del dictionary[value]


def parse_arguments():
    parser = argparse.ArgumentParser(
        prog=os.path.basename(__file__),
        description='Update Gerrit Git tags & branches',
        epilog='Update Gerrit Git tags & branches'
    )
    parser.add_argument(
        '-s', '--silent',
        help='Silent mode',
        required=False,
        action='store_true',
        default=False,
    )
    parser.add_argument(
        '-v', '--verbose',
        help='Enable verbose mode',
        required=False,
        action='count',
        default=0,
    )
    parser.add_argument(
        '-d', '--debug',
        help='Enable debug messages',
        required=False,
        action='count',
        default=0,
    )
    parser.add_argument(
        '-p', '--patchsets',
        help='List all patchets from Gerrit commits',
        required=False,
        action='count',
        default=0,
    )
    parser.add_argument(
        '-r', '--rebase',
        help='Rebase top level branches chains above the master',
        required=False,
        action='store_true',
        default=False,
    )
    parser.add_argument(
        '-j', '--subject',
        help='Add subject/commit message to branches being created',
        required=False,
        action='store_true',
        default=False,
    )
    parser.add_argument(
        '-c', '--command',
        type=str,
        required=False,
        help='User id or command')
    arguments, unknown_args = parser.parse_known_args()
    debug(f'{unknown_args}')
    if len(unknown_args) > 1:
        fatal('Too many arguments')
    arguments.exitCode = 0
    arguments.warnCount = 0
    if len(unknown_args) > 0:
        arguments.command = unknown_args[0]
    Config.debugLevel = arguments.debug
    Config.verboseLevel = arguments.verbose
    Config.rebaseChains = arguments.rebase
    Config.subjectEnabled = arguments.subject
    return arguments


class Shell:
    def __init__(self, params, silent=False):
        self.params = params
        self.silent = silent
        proc = subprocess.Popen(
            params,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE)
        stdout, stderr = proc.communicate()
        self.stdout = stdout.decode()
        self.stderr = stderr.decode()
        self.status = proc.returncode
        if not silent and not self.succed():
            error(f'Failed to execute: {self.params}')
            error(f'{self.stderr.strip()}')

    def succed(self):
        return self.status == 0

    def debug(self):
        debug(f'Shell params: {self.params}')
        debug(f'Shell stdout: {self.stdout}')
        debug(f'Shell stderr: {self.stderr}')
        debug(f'Shell status: {self.status}, succed {self.succed()}')


class GitConfig:
    def __init__(self):
        self.data = {}
        config = Shell(['git', 'config', '--list'])
        if not config.succed():
            fatal('Unable to get Git configuration')
        lines = config.stdout.split('\n')
        for line in lines:
            pos = line.find('=')
            if pos >= 0:
                key = line[0:pos]
                value = line[pos+1:]
                self.data[key] = value
                debug(f'Git configuration: key = {key} || value = {value}')
        self.user_email = self.data.get('user.email', '')
        self.repository_url = self.data.get('remote.origin.url', '')
        if self.user_email == '':
            warning('Unable to retrieve user email from Git config')
        if self.repository_url == '':
            error('Unable to retrieve repository URL')
            fatal('Looks like current directory is not a valid Git repository')


class State:
    def __init__(self):
        self.change_id = self.number = self.subject = self.email = \
            self.username = self.url = self.wip = self.patch_num = \
            self.curr_num = self.revision = self.ref = self.mode = ''
        self.parents = []
        self.child_count = 0
        self.branch_name = ''


class GerritTags:
    def __init__(self, user_email, repository_url, command, patchsets) -> None:
        self.execute = True
        self.repository_url = repository_url
        self.patchsets = patchsets
        self.email = ''
        if command is None or command == 'me' or command == '':
            self.email = user_email
        elif command == 'all':
            self.email = ''
        elif command == 'del':
            self.execute = False
        else:
            self.email = command
            if command.find('@') < 0:
                self.email += user_email[user_email.index('@'):]
        self.filter = ['status:open']
        if self.email != '':
            self.filter.append('author:'+self.email)
        self.branch_prefix = 'B/'
        self.branch_postfix = ''
        self.branch_separator = '.'
        self.branch_index = 0
        self.current_revision = ''
        self.current_branch = ''
        self.restore_branch = ''
        self.subject_limit = 65
        self.username_limit = 12
        self.gerrit_host = ''
        self.gerrit_port = []
        self.gerrit_project = ''
        self.state_list = []
        debug(f'Gerrit filter: {self.filter}')

    def remove_branches(self):
        status = Shell(['git', 'rev-parse', 'HEAD'])
        if not status.succed():
            fatal('Failed to obtain current revision')
        self.current_revision = status.stdout.strip()
        status = Shell(['git', 'rev-parse', '--abbrev-ref', 'HEAD'])
        if not status.succed():
            fatal('Failed to obtain current branch name')
        self.current_branch = status.stdout.strip()
        self.restore_branch = False
        debug(f'Curent branch {self.current_branch} at {self.current_revision}')
        status = Shell(['git', 'branch', '--format', '%(refname:short)'])
        if not status.succed():
            fatal('Unable get Git branches')
        branches = status.stdout.split('\n')
        self.branch_index = 0
        for branch_name in branches:
            if branch_name.startswith(self.branch_prefix):
                if branch_name == self.current_branch:
                    self.restore_branch = True
                    debug(f'Checking out to {self.current_revision}')
                    status = Shell(['git', 'checkout', self.current_revision])
                    if not status.succed():
                        fatal(f'Failed to checkout to {self.current_revision}')
                debug(f'Deleting local branch {branch_name}')
                if Config.unprotectGit:
                    status = Shell(['git', 'branch', '-D', branch_name])
                    if not status.succed():
                        fatal(f'Can not delete branch {branch_name}')
                self.branch_index += 1

    def git_cleanup(self):
        # status = Shell(['git', 'reflog', 'expire', '--expire-unreachable=all', '--all'])
        # if not status.succed():
        # fatal('Unable to run Git reflog expire')
        # status = Shell(['git', 'gc', '--prune=now'])
        # if not status.succed():
        # fatal('Unable to run Git gc --prune=now')
        return

    def peek_gerrit_project(self):
        status = Shell(['git', 'remote', 'show', '-n', 'origin'])
        if not status.succed():
            fatal('Failed to get remote repoistory configuration')
        lines = status.stdout.split('\n')
        for line in lines:
            pos = line.find('Push  URL:')
            if pos < 0:
                continue
            host_and_project = line[pos+10:].strip()
            exp = r'^ssh:\/\/([\w@.]+)(:(\d+))?\/([\w\/\-\+\_]+)$'
            match = re.search(exp, host_and_project)
            if match:
                self.gerrit_host = match.group(1)
                port = match.group(3)
                if port != '':
                    self.gerrit_port = ['-p', port]
                self.gerrit_project = match.group(4)
                return self.gerrit_host != '' and self.gerrit_project != ''
            return False
        return False

    def list_branches(self):
        if not self.execute:
            print(f'{Colors.green}{self.branch_index} branches has been deleted.{Colors.nc}')
            return
        status = Shell(['git', 'fetch', self.repository_url])
        if not status.succed():
            fatal(f'Failed to fetch from {self.repository_url}')
        self.branch_index = 0
        if not self.peek_gerrit_project():
            fatal(f'Failed to retrieve Gerrit project configuration from {self.repository_url}')
        args = ['ssh'] + self.gerrit_port
        args += [self.gerrit_host, 'gerrit', 'query', '--current-patch-set',
                 '--all-approvals', 'project:' + self.gerrit_project]
        status = Shell(args + self.filter)
        if not status.succed():
            fatal(f'Failed to fetch from {self.repository_url}')
        # file:///var/tmp/gerrit-project.txt
        with open('/var/tmp/gerrit-project.txt', 'w', encoding='utf-8') as project_text:
            project_text.write(status.stdout)
        lines = status.stdout.split('\n')
        # self.print_header()
        state = State()
        mode = ''
        line_index = 0
        line_count = len(lines)
        while line_index < line_count:
            line = lines[line_index]
            line_index += 1
            if line.startswith('change '):
                state = State()
                state.change_id = line[7:].strip()
                mode = 'change'
                # debug(f'{mode} || change_id = {state.change_id} mode = {mode}')
            if mode == 'change':
                if line.startswith('  number: '):
                    state.number = line[10:].strip()
                    # debug(f'{mode} || number = {state.number}')
                if line.startswith('  subject: '):
                    state.subject = line[11:].strip()
                    # debug(f'{mode} || subject = {state.subject}')
                if line.startswith('    email: '):
                    state.email = line[11:].strip()
                    # debug(f'{mode} || email = {state.email}')
                if line.startswith('    username: '):
                    state.username = line[14:].strip()
                    # debug(f'{mode} || username = {state.username}')
                if line.startswith('  url: '):
                    state.url = line[7:].strip()
                    # debug(f'{mode} || url = {state.url}')
                if line.startswith('  wip: '):
                    state.wip = line[7:].strip()
                    # debug(f'{mode} || wip = {state.wip}')
                if line.startswith('  currentPatchSet:'):
                    mode = 'currentPatchSet'
                    # debug(f'{mode} || mode = {mode}')
            if mode in ('currentPatchSet', 'patchSets'):
                if line.startswith('    number: '):
                    state.patch_num = line[12:].strip()
                    # debug(f'{mode} || patch_num = {state.patch_num}')
                    if mode == 'currentPatchSet':
                        state.curr_num = state.patch_num
                        # debug(f'{mode} || curr_num = {state.curr_num}')
                if line.startswith('    revision: '):
                    state.revision = line[14:].strip()
                    # debug(f'{mode} || revision = {state.revision}')
                if line.startswith('    ref: '):
                    state.ref = line[9:].strip()
                    mode = mode + 'Add'
                    # debug(f'{mode} || ref = {state.ref} mode = {mode}')
            if mode == 'currentPatchSet':
                if line.startswith('    parents:'):
                    succeeded = False
                    if line_index < line_count:
                        line = lines[line_index]
                        line_index += 1
                        if line.startswith(' [') and line.endswith(']'):
                            state.parents = [line[2:-1]]
                            debug(f'{mode} || ref = {state.ref} parents = {state.parents}')
                            succeeded = True
                    if not succeeded:
                        warning(f'Faild to parse parents on ref {state.revision}.')
            if mode == 'listPatchSets':
                if line.startswith('  patchSets:'):
                    state.patch_num = ''
                    state.revision = ''
                    state.ref = ''
                    mode = 'patchSets'
            if mode in ('currentPatchSetAdd', 'patchSetsAdd'):
                if state.change_id != '' and state.number != '' and \
                        state.subject != '' and state.email != '' and \
                        state.email != '' and state.url != '' and \
                        state.patch_num != '' and state.curr_num != '' and \
                        state.revision != '' and state.ref != '':
                    if mode == 'currentPatchSetAdd' or state.patch_num != state.curr_num:
                        state.mode = mode
                        self.state_list.append(state)
                        state = State()
                mode = ''
                if self.patchsets:
                    mode = 'listPatchSets'
        return

    def create_branches(self):
        state_by_rev = {}
        for state in self.state_list:
            state_by_rev[state.revision] = state
            debug(f'Revision {state.revision} registered.')
        for state in self.state_list:
            if len(state.parents) != 1:
                debug(f'Revision {state.revision} have no parent.')
                continue
            parent_rev = state.parents[0]
            if not parent_rev in state_by_rev:
                debug(f'Revision {parent_rev} not found.')
                continue
            parent = state_by_rev[parent_rev]
            parent.child_count += 1
            debug(f'Ref {parent.ref} child_count = {parent.child_count}')

        self.branch_index = 0
        self.print_header()
        for state in self.state_list:
            self.create_branch(state.mode, state)
        self.print_header()

    def create_branch(self, mode, state) -> None:
        if self.email not in ('', state.email):
            return
        # debug(f'{vars(state)}')
        entry_name = state.number
        if self.patchsets:
            entry_name = state.number + self.branch_separator + 'R' + state.patch_num
            if mode == 'currentPatchSetAdd':
                entry_name = state.number + self.branch_separator + 'CUR'
        if state.wip == 'true':
            entry_name += self.branch_separator + 'WIP'
        # if state.child_count == 0:
        #    entry_name += self.branch_separator + 'TOP'
        if self.email == '':
            entry_name += self.branch_separator + state.username
        branch_name = self.branch_prefix + entry_name + self.branch_postfix
        if Config.subjectEnabled:
            subject = re.sub(r'[^\w\s]', r'', ' ' + state.subject)
            branch_name += re.sub(r'[\s]', r'-', subject)
        state.branch_name = branch_name
        status = Shell(['git', 'branch', branch_name, state.revision], True)
        if not status.succed():
            status = Shell(['git', 'fetch', self.repository_url, state.ref])
            if not status.succed():
                fatal(f'Failed to fetch remote {state.ref} from {self.repository_url}')
            status = Shell(['git', 'branch', branch_name, state.revision], True)
            if not status.succed():
                fatal(f'Failed to create branch  {branch_name} at {state.revision}')
        status = Shell(['git', 'config', 'branch.'+branch_name + '.description',
                        state.subject], True)
        if not status.succed():
            fatal(f'Failed to set branch {branch_name} description.')
        self.print_branch(state)

    def rebase_branches(self):
        if not Config.rebaseChains:
            return
        rebase_list = []
        for state in self.state_list:
            if state.child_count != 0:
                continue
            debug(f'Rebasing branch {state.branch_name} to master')
            status = Shell(['git', 'switch', state.branch_name])
            if not status.succed():
                fatal(f'Failed to switch to {state.branch_name} branch')
            status = Shell(['git', 'rebase', '--update-refs', 'master'])
            if not status.succed():
                fatal(f'Failed to rebase branch {state.branch_name}')
            if 'is up to date' not in status.stdout:
                print(f'{status.stdout}')
                rebase_list.append(state.branch_name)
        if len(rebase_list) != 0:
            print(f'{len(rebase_list)} branches rebased: {rebase_list}')
            print('Use git push to update Git remotes.')
        else:
            print(f'{Colors.gray}There is nothing to rebase. '
                  f'All branches seems already above the \'master\' branch.{Colors.nc}')
        return

    def checkout_branch(self):
        checked_out = False
        for state in self.state_list:
            if self.current_branch == state.branch_name or self.current_revision == state.revision:
                debug(f'Checking out back to branch {state.branch_name} rev {state.revision}')
                status = Shell(['git', 'checkout', state.branch_name])
                if not status.succed():
                    fatal(f'Failed to checkout to {state.branch_name} branch')
                checked_out = True
        if not checked_out:
            if self.current_branch != 'HEAD':
                warning(f'Unable to find local branch \'{self.current_branch}\''
                        f' with rev {self.current_revision}')
            status = Shell(['git', 'checkout', self.current_revision])
            if not status.succed():
                fatal(f'Failed to checkout to branch {self.current_branch}'
                      f' revision {self.current_revision}')

    def print_header(self):
        if self.patchsets:
            index = f'{Colors.gray}---'
        else:
            index = f'{Colors.gray}--'
        user_name = ''
        if self.email == '':
            user_name = 'user'
            while len(user_name) < self.username_limit:
                user_name = '-' + user_name + '-'
            user_name = Colors.nc + ' ' + user_name[:self.username_limit]
        revision = Colors.green + '--sha1--'
        branch = Colors.blue + '--id---'
        subject = ''
        width = 0
        while width < self.subject_limit:
            subject = f'{subject}{width%10}'
            width += 1
        subject = Colors.nc + subject
        print(f'{index}{user_name} {revision} {branch} {subject}{Colors.nc} -')

    def print_branch(self, state):
        self.branch_index += 1
        index = ''
        if self.patchsets:
            index = f'{Colors.gray}{self.branch_index:03d}'
        else:
            index = f'{Colors.gray}{self.branch_index:02d}'
        revision = Colors.green + state.revision[:8]
        user_name = ''
        if self.email == '':
            user_name = state.username
            while len(user_name) < self.username_limit:
                user_name = ' ' + user_name
            user_name = Colors.nc + ' ' + user_name
        branch = Colors.blue + self.branch_prefix + state.number + self.branch_postfix
        subject = state.subject
        info = ''
        if state.child_count == 0:
            info += Colors.blue + ' *'
        if state.wip:
            info += Colors.yellow + ' WIP'
        while len(subject) < self.subject_limit:
            subject += ' '
        if len(subject) <= self.subject_limit:
            if state.wip:
                subject = Colors.yellow + subject
            else:
                subject = Colors.nc + subject
        else:
            info += Colors.red + f' [{len(subject)}>{self.subject_limit}]'
            subject = Colors.red + subject
        print(f'{index}{user_name} {revision} {branch} {subject}{Colors.nc} -'
              f'{info}{Colors.nc}')


def main():
    arguments = parse_arguments()
    git_config = GitConfig()
    debug(f'{git_config.user_email}, {arguments.command}')
    gerrit_tags = GerritTags(
        git_config.user_email,
        git_config.repository_url,
        arguments.command,
        arguments.patchsets)
    gerrit_tags.list_branches()
    gerrit_tags.remove_branches()
    gerrit_tags.create_branches()
    gerrit_tags.rebase_branches()
    gerrit_tags.checkout_branch()
    gerrit_tags.git_cleanup()


if __name__ == '__main__':
    main()
