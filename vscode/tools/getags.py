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
    def __init__(self):
        self.debug_level = 0
        self.verbose_level = 0
        self.subject_enabled = False
        self.rebase_chains = False
        self.unprotect_git = True
        self.expire_unreachable = False
        self.master_branch = 'master'
        self.patch_number = -1


config = Config()


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
    if config.debug_level > 0:
        print(f'DEBUG: {message}')


def verbose(message):
    if config.verbose_level > 0:
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


def decorate(branch):
    return f'\'{branch}\''


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
        '-u', '--patch-number',
        help='The patch number to be checked out after all',
        required=False,
        type=int,
        default=-1,
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
        help=f'Rebase top level branches chains above the {decorate(config.master_branch)}',
        required=False,
        action='store_true',
        default=False,
    )
    parser.add_argument(
        '-e', '--expire-unreachable',
        help='Prune unreachable reflog entries.',
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
    config.debug_level = arguments.debug
    config.verbose_level = arguments.verbose
    config.patch_number = arguments.patch_number
    config.rebase_chains = arguments.rebase
    config.expire_unreachable = arguments.expire_unreachable
    config.subject_enabled = arguments.subject
    return arguments


class Shell:
    def __init__(self, params, silent=False):
        self.params = params
        self.silent = silent
        proc = subprocess.Popen(
            params,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE)
        debug(f'Exec {params}')
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
        status = Shell(['git', 'config', '--list'])
        if not status.succed():
            fatal('Unable to get Git configuration')
        lines = status.stdout.split('\n')
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
        self.subject_limit = 65
        self.username_limit = 12
        self.gerrit_host = ''
        self.gerrit_port = []
        self.gerrit_project = ''
        self.state_list = []
        self.state_by_rev = {}
        self.containing_master = []
        debug(f'Gerrit filter: {self.filter}')

    def resolve_current(self):
        status = Shell(['git', 'rev-parse', 'HEAD'])
        if not status.succed():
            fatal('Failed to obtain current revision')
        self.current_revision = status.stdout.strip()
        status = Shell(['git', 'rev-parse', '--abbrev-ref', 'HEAD'])
        if not status.succed():
            fatal('Failed to obtain current branch name')
        self.current_branch = status.stdout.strip()
        debug(f'Curent branch {decorate(self.current_branch)} at {self.current_revision}')

    def remove_branches(self):
        status = Shell(['git', 'branch', '--format', '%(refname:short)'])
        if not status.succed():
            fatal('Unable get list of actual Git branches')
        branches = status.stdout.split('\n')
        self.branch_index = 0
        for branch_name in branches:
            if branch_name.startswith(self.branch_prefix):
                if branch_name == self.current_branch:
                    debug(f'Checking out to {self.current_revision}')
                    status = Shell(['git', 'checkout', self.current_revision])
                    if not status.succed():
                        fatal(f'Failed to checkout to {self.current_revision}')
                debug(f'Deleting local branch {decorate(branch_name)}')
                if config.unprotect_git:
                    status = Shell(['git', 'branch', '-D', branch_name])
                    if not status.succed():
                        fatal(f'Can not delete branch {decorate(branch_name)}')
                self.branch_index += 1

    def cleanup_pending(self):
        if not config.expire_unreachable:
            return
        status = Shell(['git', 'reflog', 'expire', '--expire-unreachable=all'])  # --all
        if not status.succed():
            fatal('Unable to run Git reflog expire')
        status = Shell(['git', 'gc', '--prune=now'])
        if not status.succed():
            fatal('Unable to run Git gc --prune=now')
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

    def obtain_branches(self):
        if not self.execute:
            print(f'{Colors.green}{self.branch_index} branches has been deleted.{Colors.nc}')
            return
        status = Shell(['git', 'checkout', config.master_branch])
        if not status.succed():
            fatal(f'Failed to checkout to {decorate(config.master_branch)}')
        status = Shell(['git', 'fetch', self.repository_url])
        if not status.succed():
            fatal(f'Failed to fetch from {self.repository_url}')
        status = Shell(['git', 'pull'])
        if not status.succed():
            fatal(f'Failed to pull {decorate(config.master_branch)} branch.')
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
                        self.state_by_rev[state.revision] = state
                        debug(f'Revision {state.revision} registered.')
                        state = State()
                mode = ''
                if self.patchsets:
                    mode = 'listPatchSets'
        return

    def find_state_by_rev(self, revision):
        if revision in self.state_by_rev:
            return self.state_by_rev[revision]
        debug(f'Revision {revision} not found.')
        return None

    def create_branches(self):
        for state in self.state_list:
            if len(state.parents) != 1:
                debug(f'Revision {state.revision} have no parent.')
                continue
            parent = self.find_state_by_rev(state.parents[0])
            if not parent:
                continue
            parent.child_count += 1
            debug(f'Ref {parent.ref} child_count = {parent.child_count}')
        self.branch_index = 0
        for state in self.state_list:
            self.create_branch(state.mode, state)
        # list branches including master
        status = Shell(['git', 'branch', '--contains', config.master_branch], True)
        if not status.succed():
            fatal(f'Failed to get list of branches containing '
                  f'{decorate(config.master_branch)} branch.')
        lines = status.stdout.split('\n')
        line_count = len(lines)
        line_index = 0
        while line_index < line_count:
            branch_name = lines[line_index]
            line_index += 1
            if branch_name.startswith('*'):
                branch_name = branch_name[1:]
            branch_name = branch_name.strip()
            if branch_name.startswith(self.branch_prefix):
                self.containing_master.append(branch_name)
        debug(f'Branchprefix {decorate(self.branch_prefix)}')
        debug(f'List of {decorate(config.master_branch)} branches: {self.containing_master}')
        # print table of the branches created
        self.print_header()
        for state in self.state_list:
            self.print_branch(state)
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
        if config.subject_enabled:
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
                fatal(f'Failed to create branch  {decorate(branch_name)} at {state.revision}')
        status = Shell(['git', 'config', 'branch.'+branch_name + '.description',
                        state.subject], True)
        if not status.succed():
            fatal(f'Failed to set branch {decorate(branch_name)} description.')

    def rebase_branches(self):
        if not config.rebase_chains:
            return
        rebase_list = []
        for state in self.state_list:
            if state.child_count != 0:
                continue
            if state.branch_name in self.containing_master:
                continue
            debug(f'Rebasing branch {decorate(state.branch_name)} '
                  f'to {decorate(config.master_branch)}')
            status = Shell(['git', 'switch', state.branch_name])
            if not status.succed():
                fatal(f'Failed to switch to {decorate(state.branch_name)} branch')
            status = Shell(['git', 'rebase', '--update-refs', config.master_branch])
            if not status.succed():
                fatal(f'Failed to rebase branch {decorate(state.branch_name)}')
            text = status.stdout.strip()
            if 'is up to date' not in text:
                if text != '':
                    print(f'{text}')
                rebase_list.append(state.branch_name)
            status = Shell(['git', 'push', 'origin', 'HEAD:refs/for/' + config.master_branch])
            if not status.succed():
                fatal(f'Failed push rebased branch {decorate(state.branch_name)}')
            text = status.stdout.strip()
            if text != '':
                print(f'{text}')
        if len(rebase_list) != 0:
            print(f'{len(rebase_list)} branches rebased: {rebase_list}')
            print('Use git push to update Git remotes.')
        else:
            print(f'{Colors.gray}There is nothing to rebase. '
                  f'All branches seems already above the {decorate(config.master_branch)}'
                  f' branch.{Colors.nc}')
        return

    def checkout_branch(self):
        if config.patch_number != -1:
            if self.checkout_to(str(config.patch_number), '', ''):
                return
            warning(f'Failed to check out to patch numver {config.patch_number}')
        debug(f'Checking out branch {decorate(self.current_branch)} '
              f'revision {self.current_revision}')
        if not self.checkout_to('', self.current_branch, self.current_revision):
            known_branch = self.current_branch == 'HEAD' or \
                self.current_branch == config.master_branch
            chekout_target = self.current_branch
            if not known_branch:
                chekout_target = self.current_revision
                warning(f'Unable to find local branch {decorate(self.current_branch)}'
                        f' with rev {self.current_revision}')
            status = Shell(['git', 'checkout', chekout_target])
            if not status.succed():
                fatal(f'Failed to checkout to branch {decorate(self.current_branch)}'
                      f' revision {self.current_revision}')

    def checkout_to(self, patch_number, branch_name, revision):
        for state in self.state_list:
            if patch_number == state.number or \
                    branch_name == state.branch_name or \
                    revision == state.revision:
                debug(f'Checking out back to branch {decorate(state.branch_name)} '
                      f'revision {state.revision}')
                status = Shell(['git', 'checkout', state.branch_name])
                if not status.succed():
                    fatal(f'Failed to checkout to {decorate(state.branch_name)} branch')
                return True
        return False

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
        print(f'{index}{user_name} {revision} {branch} {subject}{Colors.nc} | ----- |')

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
        post = Colors.nc + '  '
        info += Colors.blue + ' *' if state.child_count == 0 else post
        info += Colors.yellow + ' W' if state.wip else post
        info += Colors.cyan + ' R' if state.branch_name not in self.containing_master else post
        info += Colors.nc + ' |'
        while len(subject) < self.subject_limit:
            subject += ' '
        if len(subject) <= self.subject_limit:
            if state.wip:
                subject = Colors.yellow + subject
            else:
                subject = Colors.nc + subject
        else:
            info += Colors.red + f' [{len(subject)}>{self.subject_limit}]'
            subject = Colors.red + subject[:self.subject_limit-3] + '...'
        print(f'{index}{user_name} {revision} {branch} {subject}{Colors.nc} |'
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
    gerrit_tags.resolve_current()
    gerrit_tags.obtain_branches()
    gerrit_tags.remove_branches()
    gerrit_tags.create_branches()
    gerrit_tags.rebase_branches()
    gerrit_tags.checkout_branch()
    gerrit_tags.cleanup_pending()


if __name__ == '__main__':
    main()
