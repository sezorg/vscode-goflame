#!/usr/bin/env python3
# Copyright 2025 RnD Center "ELVEES", JSC

#
# According to the current `git diff', perform a line length constraint analysis to filter the
# results of other static analyzers and other tools.
#

# pylint: disable=bad-indentation
# pylint: disable=invalid-name
# pylint: disable=missing-class-docstring
# pylint: disable=missing-function-docstring
# pylint: disable=missing-module-docstring
# pylint: disable=too-few-public-methods
# pylint: disable=too-many-branches
# pylint: disable=too-many-instance-attributes
# pylint: disable=too-many-statements

import argparse
import io
import os
import re
import select
import subprocess
import sys
import unidiff


class Config:
    debugLevel = 0
    verboseLevel = 0
    lineLengthLimit = 0
    tabWidth = 0
    parseStdin = False
    excludeList = ""
    gitCommit = ""
    excludeNonPrefixed = False
    excludeNolintWarns = False
    printAll = False
    printAny = False
    noLintList = []
    prefixA = ''
    prefixB = ''


class State:
    exitCode = 0
    prevWrite = ''
    writeCount = 0


class Colors:
    red = '\033[31m'
    green = '\033[32m'
    yellow = '\033[33m'
    blue = '\033[34m'
    gray = '\033[90m'
    nc = '\033[0m'
    cregexp = r's/\033\[([0-9]{1,3}(;[0-9]{1,3})*)?[mGK]//g'
    header = '\033[95m'
    cyan = '\033[96m'
    warning = '\033[93m'
    fail = '\033[91m'
    endc = '\033[0m'
    bold = '\033[1m'
    under = '\033[4m'


def write(message):
    if Config.prefixA != '' and \
            not message.startswith(Config.prefixA) and not Config.prefixB in message:
        match = re.match(r'([^:]*):([0-9]+:)?([0-9]+:)?(.*)', message)
        if match:
            message = match.group(1)+':'+to_string(match.group(2)) +\
                to_string(match.group(3))+Config.prefixB+match.group(4)
        else:
            message = Config.prefixA + message
    new_write = re.sub(r'[^a-zA-Z0-9 -]', '', message)
    if State.prevWrite != new_write:
        State.prevWrite = new_write
        State.writeCount = State.writeCount + 1
        print(message)


def to_string(value):
    if value is not None:
        return str(value)
    return ''


def debug(message):
    if Config.debugLevel > 0:
        write(f'DEBUG: {Config.prefixA}{message}')


def debug0(message):
    write(f'DEBUG0: {Config.prefixA}{message}')


def verbose(message):
    if Config.verboseLevel > 0:
        write(f'VERBOSE: {Config.prefixA}{message}')


def warning(message):
    write(f'{Colors.yellow}WARNING: {Config.prefixA}{message}{Colors.nc}')


def error(message):
    write(f'{Colors.red}ERROR: {Config.prefixA}{message}{Colors.nc}')


def fatal(message):
    write(f'{Colors.red}FATAL: {Config.prefixA}{message}{Colors.nc}')
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
        '-l', '--line-length-limit',
        help='Set line length limit to N characters',
        required=False,
        type=int,
        default=100,
    )
    parser.add_argument(
        '-t', '--tab-width',
        help='Extend tabs with N characters',
        required=False,
        type=int,
        default=4,
    )
    parser.add_argument(
        '-p', '--parse-stdin',
        help='Parse STDIN and suppress messages which does not belongs to current `git diff`',
        required=False,
        action='store_true',
        default=False,
    )
    parser.add_argument(
        '-e', '--exclude-list',
        help='Suppress messages outside current patch set',
        required=False,
        type=str,
        default="",
    )
    parser.add_argument(
        '-c', '--commit',
        help='Use specified commit for git diff',
        required=False,
        type=str,
        default="",
    )
    parser.add_argument(
        '-x', '--exclude-non-prefixed',
        help='Exclude strings without proper `file:line:` prefix',
        required=False,
        action='store_true',
        default=False,
    )
    parser.add_argument(
        '-z', '--exclude-nolint',
        help='Exclude warnings about unknown linters in nolint directives',
        required=False,
        action='store_true',
        default=False,
    )
    parser.add_argument(
        '-a', '--print-all',
        help='Print all messages regardless of changeset or commit',
        required=False,
        action='store_true',
        default=False,
    )
    parser.add_argument(
        '-r', '--print-any',
        help='Print any messages then all suppressed',
        required=False,
        action='store_true',
        default=False,
    )
    parser.add_argument(
        '-n', '--nolint',
        help='Comma separated list of suppressed linters',
        required=False,
        type=str,
        default="",
    )
    parser.add_argument(
        '--prefix',
        help='Set prefix to diagnostic messages',
        required=False,
        type=str,
        default="",
    )
    arguments, unknown_args = parser.parse_known_args()
    Config.debugLevel = arguments.debug
    debug(f'arguments={arguments}')
    if len(unknown_args) > 1:
        fatal('Too many arguments')
    if len(unknown_args) > 0:
        arguments.command = unknown_args[0]
    Config.verboseLevel = arguments.verbose
    Config.lineLengthLimit = arguments.line_length_limit
    Config.tabWidth = arguments.tab_width
    Config.parseStdin = arguments.parse_stdin
    Config.excludeList = arguments.exclude_list
    Config.gitCommit = arguments.commit
    Config.excludeNonPrefixed = arguments.exclude_non_prefixed
    Config.excludeNolintWarns = arguments.exclude_nolint
    Config.printAll = arguments.print_all
    Config.printAny = arguments.print_any
    Config.noLintList = arguments.nolint.split(',')
    if arguments.prefix != '':
        Config.prefixA = arguments.prefix + ': '
        Config.prefixB = ' ' + arguments.prefix + ':'
    return arguments


class Shell:
    def __init__(self, params, silent=False):
        args = ' '.join(map(str, params))
        debug(f'Shell: {args}')
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
        if not silent and not self.succeed():
            error(f'Failed to execute: {self.params}')
            error(f'{self.stderr.strip()}')

    def succeed(self):
        return self.status == 0

    def debug(self):
        debug(f'Shell params: {self.params}')
        debug(f'Shell stdout: {self.stdout}')
        debug(f'Shell stderr: {self.stderr}')
        debug(f'Shell status: {self.status}, succeed {self.succeed()}')
        return


class GitChangeSet:
    def __init__(self, file_path, appended_lines, deleted_lines):
        self.file_path = file_path
        self.deleted_lines = deleted_lines
        self.appended_lines = appended_lines
        return


class GitDiff:
    def __init__(self):
        self.have_git_dir = os.path.isdir(os.path.join(os.getcwd(), '.git'))
        self.change_list = []
        if not self.have_git_dir:
            return
        commit = Config.gitCommit
        postfix = '~'
        result = Shell(['git', 'status'])
        if not result.succeed():
            fatal('Unable to run \'git status\' on project')
        if 'interactive rebase in progress' in result.stdout:
            expr = r'interactive rebase in progress; onto ([\w]+)'
            match = re.match(expr, result.stdout)
            if not match:
                fatal('Unable to get \'git rebase\' commit')
            commit = match.group(1)
            postfix = ''
        if commit != '':
            commit += postfix
        self.run_on_commit(commit, '')
        result = Shell(['git', 'ls-files', '--others', '--exclude-standard'])
        if not result.succeed():
            fatal('Unable to get \'git\' untracked files')
        for file_path in result.stdout.split('\n'):
            if file_path == '':
                continue
            file_name = os.path.basename(file_path)
            if file_name.startswith('zz_') or file_name.startswith('zzz_'):
                continue
            debug(f'Appended untracked file: {file_path}')
            change_set = GitChangeSet(file_path, [], None)
            self.change_list.append(change_set)
        return

    def run_on_commit(self, commit_in, commit_out):
        arguments = ['git', 'diff']  # '--cached', '--merge-base'
        if commit_in != "":
            arguments.append(commit_in)
        if commit_out != "":
            arguments.append(commit_out)
        result = Shell(arguments)
        if not result.succeed():
            fatal('Unable to run \'git diff\' on project')
        diff_path = "/var/tmp/diff-check.diff"
        with open(diff_path, 'w', encoding='utf-8') as file:
            file.write(f'Diff: {commit_in}..{commit_out}')
            file.write(result.stdout)
        text = io.StringIO(result.stdout)
        patch_set = unidiff.PatchSet(text)
        for patched_file in patch_set:
            appended_lines = [line for hunk in patched_file for line in hunk
                              if line.is_added and line.value.strip() != '']
            if len(appended_lines) == 0 or not os.path.isfile(patched_file.path):
                continue
            debug(f'Appended diff file: {patched_file.path}')
            change_set = GitChangeSet(patched_file.path, appended_lines, None)
            self.change_list.append(change_set)
        return


class GitFiles:
    def __init__(self):
        config = Shell(['git', 'ls-tree', '-r', 'master', '--name-only'])
        if not config.succeed():
            fatal('Unable to run \'git diff\' on project')
        self.files = config.stdout.split('\n')


class GitPatchLines:
    def __init__(self, git_diff):
        self.patched_lines = {}
        for change_set in git_diff.change_list:
            file_path = change_set.file_path
            if len(change_set.appended_lines) == 0:
                key = f'{file_path}:'
                self.patched_lines[key] = True
            else:
                for line in change_set.appended_lines:
                    key = f'{file_path}:{line.target_line_no}:'
                    self.patched_lines[key] = True
        return

    def get(self):
        return self.patched_lines


class BuiltinLintersRunner:
    def __init__(self, git_diff):
        self.git_diff = git_diff
        self.file_path = ''
        self.line_index = 0
        self.line_text = ''
        self.in_imports = 0
        self.in_hdrcheck = 0
        return

    def run(self):
        if not self.git_diff.have_git_dir:
            return
        if Config.printAll:
            self.process_all()
            return
        for change_set in self.git_diff.change_list:
            self.file_path = change_set.file_path
            self.in_imports = 0
            self.in_hdrcheck = 0
            need_file = False
            debug(f'Running DIFF on {self.file_path}')
            for line in change_set.appended_lines:
                need_file = True
                self.line_index = line.target_line_no
                self.line_text = line.value.rstrip('\r\n').expandtabs(Config.tabWidth)
                debug(f'Diff: {self.file_path}:{self.line_index}: {self.line_text}')
                self.process_diff()
            if need_file:
                debug(f'Running FULL-A on {self.file_path}')
                self.process_file(False, True)
            if len(change_set.appended_lines) == 0:
                debug(f'Running FULL-B on {self.file_path}')
                self.process_file(True, False)
        return

    def process_all(self):
        git_files = GitFiles()
        for self.file_path in git_files.files:
            self.file_path = self.file_path.strip()
            self.in_imports = 0
            self.in_hdrcheck = 0
            if self.file_path == "":
                continue
            self.process_file(True, True)
        return

    def process_file(self, diff_check, full_check):
        if not os.path.isfile(self.file_path):
            return
        with open(self.file_path, "rb") as file:
            zero_count = 0
            section = file.read(1024)
            for value in section:
                if value == 0:
                    zero_count = zero_count + 1
            if zero_count > len(section) / 200:
                return
        lines = open(self.file_path, 'r', encoding='utf-8').readlines()
        for index, line in enumerate(lines):
            self.line_index = index + 1
            self.line_text = line.rstrip('\r\n').expandtabs(Config.tabWidth)
            if diff_check:
                self.process_diff()
            if full_check:
                self.process_full()
        return

    def process_diff(self):
        self.process_lllcheck()
        self.process_wrapcheck()
        self.process_declcheck()
        self.process_deprecheck()
        return

    def process_full(self):
        self.process_ghdrcheck()
        self.process_gimpcheck()
        return

    def process_lllcheck(self):
        type_id = 'lll'
        length = len(self.line_text)
        if length > Config.lineLengthLimit and self.line_text[length-1] != '`':
            if self.file_path in ['go.mod', 'go.sum']:
                return
            if self.is_suppressed(type_id):
                return
            self.output_message(type_id, 'Maximum line length exceeded '
                                f'({length} > {Config.lineLengthLimit})')
        return

    def process_wrapcheck(self):
        type_id = 'wrapcheck'
        check_list = ['fmt.'+'Error', 'errors.'+'Wrap', 'errors.'+'New', 'errors.'+'Error']
        offset = - 1
        for check in check_list:
            offset = self.line_text.find(check)
            if offset >= 0:
                break
        if offset < 0:
            return False
        if self.is_suppressed(type_id):
            return
        length = len(self.line_text)
        while offset < length and self.line_text[offset] != '"':
            offset += 1
        if offset < length - 1 and self.line_text[offset] == '"':
            offset += 1
            start = self.line_text[offset]
            if str.isalpha(start) and not str.islower(start):
                word = BuiltinLintersRunner.select_first_alnum_word(
                    self.line_text[offset:].split()[0])
                self.process_wrapcheck_word(type_id, word)
        else:
            self.output_message(
                type_id, 'Unable to figure out error string. Consider to use one-line expression')
        return

    def process_wrapcheck_word(self, type_id, word):
        index = 0
        length = len(word)
        while index < length:
            char = word[index]
            if not char.isupper() and not char.isdigit():
                break
            index = index + 1
        upper = index
        while index < length:
            char = word[index]
            if char.isupper() or char.isdigit():
                break
            index = index + 1
        lower = index
        if lower == length and upper == 1 and upper != length:
            self.output_message(type_id, f'Error strings should not be capitalized: \'{word}\'')
        return

    def process_declcheck(self):
        type_id = 'declcheck'
        if self.line_text.replace(" ", "").find(':'+'nil') >= 0 and not self.is_suppressed(type_id):
            self.output_message(type_id, 'Nil field initialization can be omitted')
            return
        offset = self.line_text.find(':=')
        if offset < 0:
            return False
        if self.line_text.endswith('""') and not self.is_suppressed(type_id):
            self.output_message(type_id, 'Consider initializing an empty string with var keyword')
            return
        if ((self.line_text.find('[]') >= 0 and self.line_text.endswith('{}')) or
                self.line_text.endswith('(nil)')) and not self.is_suppressed(type_id):
            self.output_message(type_id, 'Explicit variable declaration should use var keyword')
        return

    def process_deprecheck(self):
        type_id = 'deprecheck'
        check_list = ['errors.'+'Wrap']
        offset = - 1
        check = ''
        for check in check_list:
            offset = self.line_text.find(check)
            if offset >= 0:
                break
        if offset < 0:
            return False
        if self.is_suppressed(type_id):
            return
        self.output_message(type_id, f'Use of method is deprecated: \'{check}\'')
        return

    def process_ghdrcheck(self):
        type_id = 'ghdrcheck'
        if self.in_hdrcheck == 0 and self.line_text != '':
            self.in_hdrcheck = 1
            if self.line_text.startswith('/*'):
                self.output_message_no_code(
                    type_id, 'Consider using \'//\' instead of \'/*\' in header comment')
        return

    def process_gimpcheck(self):
        type_id = 'gimpcheck'
        if self.in_imports < 0:
            return
        if self.line_text.startswith('import ('):
            self.in_imports = 1
        elif self.in_imports == 0:
            return
        elif self.line_text == '':
            self.in_imports += 1
        elif self.line_text.startswith(')'):
            if self.in_imports > 2 and not self.is_suppressed(type_id):
                self.output_message_no_code(type_id, 'Multiple separator lines in imports block' +
                                            f' (actual {self.in_imports-1}, max 1)')
            self.in_imports = -1
            return
        return

    def is_suppressed(self, suppress):
        if suppress in Config.noLintList:
            return True
        prefix = 'nolint:'
        offset = self.line_text.rfind(prefix)
        if offset < 0:
            return False
        for option in self.line_text[offset+len(prefix):].split(','):
            option = option.strip()
            if option == suppress:
                return True
            if option == '':
                return False
        return False

    def output_message_no_code(self, type_id, message):
        if self.is_suppressed(type_id):
            return '', False
        prefix = f'{self.file_path}:{self.line_index}: '
        write(f'{prefix}{message} ({type_id})')
        State.exitCode = 2
        return prefix, True

    def output_message(self, type_id, message):
        prefix, enable = self.output_message_no_code(type_id, message)
        if enable and not Config.excludeNonPrefixed:
            write(f'{prefix}{self.line_text} ({type_id})')
        return enable

    @staticmethod
    def select_first_alnum_word(string):
        match = re.search(r'\b\w+\b', string)
        if match:
            return match.group()
        else:
            return None


class WarningsSuppressor:
    def __init__(self, git_diff):
        self.git_diff = git_diff
        self.previous_line = ''
        self.output_next = False
        self.output_count = 0
        return

    def run(self):
        debug('starting WarningsSuppressor')
        have_exclude_list = Config.excludeList != ""
        identifiers = Config.excludeList.split(',')
        debug(f'suppression list={identifiers}')
        suppress_list = {}
        for identifier in identifiers:
            suppress_list[identifier] = True
        patched_lines = GitPatchLines(self.git_diff).get()
        input_lines = sys.stdin.readlines()
        if not self.git_diff.have_git_dir:
            for line in input_lines:
                self.output(line + ' [no-git]', False, 5)
            return
        self.previous_line = ''
        self.output_next = False
        for line in input_lines:
            line = line.rstrip('\r\n')
            if line == self.previous_line:
                continue
            prefixed = line.startswith('level=')
            if prefixed and Config.excludeNolintWarns and (
                    line.find('msg="[runner/nolint]') >= 0 or
                    line.find('[runner/nolint_filter]') >= 0):
                continue
            if self.output_next or prefixed:
                self.output(line, prefixed, 1)
                continue
            words = line.split()
            if len(words) == 0:
                continue
            match = re.match(r'([^:]*):([0-9]+):([0-9]+):', words[0])
            if match:
                words[0] = f'{match.group(1)}:{match.group(2)}:'
                words.append(f'{match.group(1)}:')
            if have_exclude_list and self.in_dictionary(words, suppress_list):
                continue
            if self.in_dictionary(words, patched_lines):
                self.output(line, prefixed, 2)
            elif Config.printAll:
                if not Config.excludeNonPrefixed:
                    self.output(line + ' [not-in-diff]', prefixed, 3)
                elif re.match(r'([^:]*):([0-9]+):', words[0]):
                    self.output(line + ' [not-in-diff]', prefixed, 4)
        if self.output_count == 0 and Config.printAny:
            for line in input_lines:
                self.output(line, False, 5)
        return

    def output(self, line, prefixed, exit_code):
        if self.output_skip(line):
            return
        output = line
        if prefixed:
            prefixes = ['WARNING: ', 'ERROR: ']
            for index, prefix in enumerate(['level=warning msg="', 'level=error msg="']):
                if output.startswith(prefix):
                    output = prefixes[index] + output[len(prefix):-1]
                    output = output.replace('\\n', '\n')
                    output = output.replace('\\r', '\n')
                    output = output.replace('\\t', '\t')
        self.output_count = self.output_count + 1
        write(output)
        self.previous_line = line
        self.output_next = line.endswith(':')
        State.exitCode = exit_code
        return

    def output_skip(self, line):
        if self.previous_line == line:
            return True
        if self.output_next:
            return False
        if not line.endswith(')'):
            return False
        expr = r'^(.*)\s+\(\w+\)$'
        old_match = re.match(expr, self.previous_line)
        if not old_match:
            return False
        new_match = re.match(expr, line)
        if not new_match:
            return False
        old_text = old_match.group(1).removesuffix(')')
        new_text = new_match.group(1).removesuffix(')')
        return old_text == new_text

    def in_dictionary(self, words, dictionary):
        for word in words:
            if word in dictionary:
                return True
        return False


def main():
    parse_arguments()
    git_diff = GitDiff()
    if Config.parseStdin or select.select([sys.stdin, ], [], [], 0.0)[0]:
        debug('Starting WarningsSuppressor...')
        WarningsSuppressor(git_diff).run()
    else:
        debug('Starting BuiltinLintersRunner...')
        BuiltinLintersRunner(git_diff).run()
    sys.exit(State.exitCode)


if __name__ == '__main__':
    main()
