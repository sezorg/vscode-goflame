#!/usr/bin/env python3

#
# According to the current `git diff', perform a line length constraint analysis to filter the
# results of other static analyzers and other tools.
#

# pylint: disable=missing-module-docstring
# pylint: disable=missing-class-docstring
# pylint: disable=missing-function-docstring
# pylint: disable=bad-indentation
# pylint: disable=too-few-public-methods
# pylint: disable=too-many-branches
# pylint: disable=too-many-statements
# pylint: disable=too-many-instance-attributes

import argparse
import io
import os
import re
import select
import subprocess
import sys

unidiff = __import__("py-unidiff")


class Config:
    debugLevel = 0
    verboseLevel = 0
    lineLengthLimit = 0
    tabWidth = 0
    parseInput = False
    excludeList = ""
    gitCommit = ""
    excludeNonPrefixed = False
    excludeNolintWarns = False
    printAll = False
    exitCode = 0


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
        '-l', '--line-length-limit',
        help='Set line length limit to N characters',
        required=False,
        type=int,
        default=100,
    )
    parser.add_argument(
        '-t', '--tab-width',
        help='Extand tabs with N characters',
        required=False,
        type=int,
        default=4,
    )
    parser.add_argument(
        '-p', '--parse-input',
        help='Parse STDIN and suppress messages whis does not belongs to current `git diff`',
        required=False,
        action='store_true',
        default=False,
    )
    parser.add_argument(
        '-e', '--exclude-list',
        help='Supress messages outside current patch set',
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
        help='Exclude warnings about unknown linters in nolint derectives',
        required=False,
        action='store_true',
        default=False,
    )
    parser.add_argument(
        '-a', '--print-all',
        help='Print all messages regardless of changeset or commint',
        required=False,
        action='store_true',
        default=False,
    )
    arguments, unknown_args = parser.parse_known_args()
    Config.debugLevel = arguments.debug
    # debug(f'arguments={arguments}')
    # debug(f'unknown arguments={unknown_args}')
    if len(unknown_args) > 1:
        fatal('Too many arguments')
    arguments.exitCode = 0
    arguments.warnCount = 0
    if len(unknown_args) > 0:
        arguments.command = unknown_args[0]
    Config.debugLevel = arguments.debug
    Config.verboseLevel = arguments.verbose
    Config.lineLengthLimit = arguments.line_length_limit
    Config.tabWidth = arguments.tab_width
    Config.parseInput = arguments.parse_input
    Config.excludeList = arguments.exclude_list
    Config.gitCommit = arguments.commit
    Config.excludeNonPrefixed = arguments.exclude_non_prefixed
    Config.excludeNolintWarns = arguments.exclude_nolint
    Config.printAll = arguments.print_all
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
        # debug(f'Shell params: {self.params}')
        # debug(f'Shell stdout: {self.stdout}')
        # debug(f'Shell stderr: {self.stderr}')
        # debug(f'Shell status: {self.status}, succed {self.succed()}')
        return


class GitChangeSet:
    def __init__(self, file_path, appended_lines, deleted_lines):
        self.file_path = file_path
        self.deleted_lines = deleted_lines
        self.appended_lines = appended_lines
        return


class GitDiff:
    def __init__(self):
        self.change_list = []
        result = Shell(['git', 'status'])
        if not result.succed():
            fatal('Unable to run \'git status\' on project')
        if 'interactive rebase in progress' in result.stdout:
            expr = r'interactive rebase in progress; onto ([\w]+)'
            match = re.match(expr, result.stdout)
            if not match:
                fatal('Unable to get \'git rebase\' commit')
            commit = match.group(1)
            self.run_on_commit(commit, '', '', '')
            return
        commit = Config.gitCommit
        self.run_on_commit(commit, '~', '', '')
        return

    def run_on_commit(self, commit_in, commit_in_post, commit_out, commit_out_post):
        argumens = ['git', 'diff']
        if commit_in != "":
            argumens.append(commit_in + commit_in_post)
        if commit_out != "":
            argumens.append(commit_out + commit_out_post)
        result = Shell(argumens)
        if not result.succed():
            fatal('Unable to run \'git diff\' on project')
        text = io.StringIO(result.stdout)
        patch_set = unidiff.PatchSet(text)
        for patched_file in patch_set:
            appended_lines = [line for hunk in patched_file for line in hunk
                              if line.is_added and line.value.strip() != '']
            # debug(f'{appended_lines}')
            file_path = patched_file.path
            change_set = GitChangeSet(file_path, appended_lines, None)
            self.change_list.append(change_set)
        return


class GitFiles:
    def __init__(self):
        config = Shell(['git', 'ls-tree', '-r', 'master', '--name-only'])
        if not config.succed():
            fatal('Unable to run \'git diff\' on project')
        self.files = config.stdout.split('\n')


class GitPatchLines:
    def __init__(self, git_diff):
        self.patched_lines = {}
        for change_set in git_diff.change_list:
            file_path = change_set.file_path
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
        return

    def run(self):
        if Config.printAll:
            self.process_all()
            return
        for change_set in self.git_diff.change_list:
            for line in change_set.appended_lines:

                self.file_path = change_set.file_path
                self.line_index = line.target_line_no
                self.line_text = line.value.rstrip(
                    '\r\n').expandtabs(Config.tabWidth)
                debug(
                    f'Change: {self.file_path}:{self.line_index}: {self.line_text}')
                self.process_line()
        return

    def process_all(self):
        git_files = GitFiles()
        for self.file_path in git_files.files:
            self.file_path = self.file_path.strip()
            if self.file_path == "":
                continue
            lines = open(self.file_path, 'r', encoding='utf-8').readlines()
            for index, line in enumerate(lines):
                self.line_index = index + 1
                self.line_text = line.expandtabs(Config.tabWidth)
                self.process_line()
        return

    def process_line(self):
        self.process_lllcheck()
        self.process_wrapcheck()
        self.process_declcheck()
        self.process_deprecheck()
        # self.process_gimpcheck()
        return

    def process_lllcheck(self):
        type_id = 'lll'
        length = len(self.line_text)
        if length > Config.lineLengthLimit and self.line_text[length-1] != '`':
            if self.file_path in ['go.mod', 'go.sum']:
                return
            if self.is_supressed(type_id):
                return
            self.output_message(type_id, 'Maximum line length exceeded '
                                f'({length} > {Config.lineLengthLimit})')
        return

    def process_wrapcheck(self):
        type_id = 'wrapcheck'
        check_list = ['fmt.Error', 'errors.Wrap', 'errors.New', 'errors.Error']
        offset = - 1
        for check in check_list:
            offset = self.line_text.find(check)
            if offset >= 0:
                break
        if offset < 0:
            return False
        if self.is_supressed(type_id):
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
                if len(word) == 1 or word.upper() != word:
                    self.output_message(
                        type_id, f'Error strings should not be capitalized: \'{word}\'')
        else:
            self.output_message(
                type_id, 'Unable to filed error string. Consider to use one-line expression')
        return

    def process_declcheck(self):
        type_id = 'declcheck'
        if self.line_text.replace(" ", "").find(':nil') >= 0 and not self.is_supressed(type_id):
            self.output_message(type_id, 'Nil field initialization can be omitted')
            return
        offset = self.line_text.find(':=')
        if offset < 0:
            return False
        if self.line_text.endswith('""') and not self.is_supressed(type_id):
            self.output_message(type_id, 'Consider initializing an empty string with var keyword')
            return
        if ((self.line_text.find('[]') >= 0 and self.line_text.endswith('{}')) or
                self.line_text.endswith('(nil)')) and not self.is_supressed(type_id):
            self.output_message(type_id, 'Explicit variable declaration should use var keyword')
        return

    def process_deprecheck(self):
        type_id = 'deprecheck'
        check_list = ['errors.Wrap']
        offset = - 1
        check = ''
        for check in check_list:
            offset = self.line_text.find(check)
            if offset >= 0:
                break
        if offset < 0:
            return False
        if self.is_supressed(type_id):
            return
        self.output_message(type_id, f'Use of method is deprecated: \'{check}\'')
        return

    def process_gimpcheck(self):
        type_id = 'gimpcheck'
        if self.line_text.startswith('import ('):
            self.in_imports = 1
            self.output_message(type_id, 'Sep start')
            return
        if self.in_imports != 0:
            if self.line_text == '':
                self.in_imports += 1
                self.output_message(type_id, 'Sep space')
                return
            if self.line_text.startswith(')'):
                self.output_message(type_id, f'Sep end {self.in_imports}')
                if self.in_imports > 2 and not self.is_supressed(type_id):
                    self.output_message(type_id, 'Multiple separator lines in imports block')
                self.in_imports = 0
                return
        return

    def is_supressed(self, supress):
        prefix = 'nolint:'
        offset = self.line_text.rfind(prefix)
        if offset < 0:
            return False
        for option in self.line_text[offset+len(prefix):].split(','):
            option = option.strip()
            if option == supress:
                return True
            if option == '':
                return False
        return False

    def output_message(self, type_id, message):
        if self.is_supressed(type_id):
            return
        prefix = f'{self.file_path}:{self.line_index}: '
        print(f'{prefix}{message} ({type_id})')
        if not Config.excludeNonPrefixed:
            print(f'{prefix}{self.line_text} ({type_id})')
        Config.exitCode = 2

    @staticmethod
    def select_first_alnum_word(string):
        match = re.search(r'\b\w+\b', string)
        if match:
            return match.group()
        else:
            return None


class WarningsSupressor:
    def __init__(self, git_diff):
        self.git_diff = git_diff
        self.previous_line = ''
        self.output_next = False
        return

    def run(self):
        have_exclude_list = Config.excludeList != ""
        identifiers = Config.excludeList.split(',')
        # debug(f'supression list={identifiers}')
        supress_list = {}
        for identifier in identifiers:
            supress_list[identifier] = True
        patched_lines = GitPatchLines(self.git_diff).get()
        input_lines = sys.stdin.readlines()
        self.previous_line = ''
        self.output_next = False
        for line in input_lines:
            line = line.rstrip('\r\n')
            if line == self.previous_line:
                continue
            prefixed = line.startswith('level=')
            if prefixed and Config.excludeNolintWarns and line.index('msg="[runner/nolint]') >= 0:
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
            if self.in_dictionary(words, patched_lines):
                self.output(line, prefixed, 2)
            elif (Config.printAll or (
                    have_exclude_list and not self.in_dictionary(words, supress_list))):
                if not Config.excludeNonPrefixed:
                    self.output(line + ' [not-in-diff]', prefixed, 3)
                elif re.match(r'([^:]*):([0-9]+):', words[0]):
                    self.output(line + ' [not-in-diff]', prefixed, 4)
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
        print(output)
        self.previous_line = line
        self.output_next = line.endswith(':')
        Config.exitCode = exit_code
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
    if Config.parseInput or select.select([sys.stdin, ], [], [], 0.0)[0]:
        debug('Starting WarningsSupressor...')
        WarningsSupressor(git_diff).run()
    else:
        debug('Starting BuiltinLintersRunner...')
        BuiltinLintersRunner(git_diff).run()
    sys.exit(Config.exitCode)


if __name__ == '__main__':
    main()
