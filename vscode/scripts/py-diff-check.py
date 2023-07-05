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
        '-a', '--print-all',
        help='Print all messages regardless of changeset or commint',
        required=False,
        action='store_true',
        default=False,
    )
    arguments, unknown_args = parser.parse_known_args()
    Config.debugLevel = arguments.debug
    debug(f'arguments={arguments}')
    debug(f'unknown arguments={unknown_args}')
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
        debug(f'Shell params: {self.params}')
        debug(f'Shell stdout: {self.stdout}')
        debug(f'Shell stderr: {self.stderr}')
        debug(f'Shell status: {self.status}, succed {self.succed()}')


class GitChangeSet:
    def __init__(self, file_path, appended_lines, deleted_lines):
        self.file_path = file_path
        self.deleted_lines = deleted_lines
        self.appended_lines = appended_lines
        return


class GitDiff:
    def __init__(self):
        self.data = {}
        argumens = ['git', 'diff']
        if Config.gitCommit != "":
            argumens.append(Config.gitCommit+'~')
            argumens.append(Config.gitCommit)
        config = Shell(argumens)
        if not config.succed():
            fatal('Unable to run \'git diff\' on project')
        text = io.StringIO(config.stdout)
        patch_set = unidiff.PatchSet(text)
        self.change_list = []
        for patched_file in patch_set:
            appended_lines = [line for hunk in patched_file for line in hunk
                              if line.is_added and line.value.strip() != '']
            # deleted_lines = [line for hunk in patched_file
            #                  for line in hunk if line.is_removed and
            #                  line.value.strip() != '']
            debug(f'{appended_lines}')
            file_path = patched_file.path
            change_set = GitChangeSet(file_path, appended_lines, None)
            self.change_list.append(change_set)
        # debug(f'change_list={self.change_list}')
        return


class GitFiles:
    def __init__(self):
        self.data = {}
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


class LineLengthLimit:
    def __init__(self, git_diff):
        self.git_diff = git_diff
        return

    def run(self):
        if Config.printAll:
            self.process_all()
            return
        for change_set in self.git_diff.change_list:
            for line in change_set.appended_lines:
                text = line.value.rstrip('\r\n').expandtabs(Config.tabWidth)
                self.process_line(change_set.file_path,
                                  line.target_line_no, text)
        return

    def process_all(self):
        git_files = GitFiles()
        for file_path in git_files.files:
            file_path = file_path.strip()
            if file_path == "":
                continue
            lines = open(file_path, 'r', encoding='utf-8').readlines()
            for line_index, line in enumerate(lines):
                self.process_line(file_path, line_index+1, line)
        return

    def process_line(self, file_path, line_index, line):
        text = line.expandtabs(Config.tabWidth)
        length = len(text)
        if length > Config.lineLengthLimit:
            prefix = f'{file_path}:{line_index}: '
            print(f'{prefix}Maximum line length exceeded '
                  f'({length} > {Config.lineLengthLimit})')
            if not Config.excludeNonPrefixed:
                print(f'{prefix}{text}')
            Config.exitCode = 1


class WarningsSupressor:
    def __init__(self, git_diff):
        self.git_diff = git_diff
        self.previous_line = ''
        self.output_next = False
        return

    def run(self):
        have_exclude_list = Config.excludeList != ""
        identifiers = Config.excludeList.split(',')
        debug(f'supression list={identifiers}')
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
                    self.output(line, prefixed, 3)
                elif re.match(r'([^:]*):([0-9]+):', words[0]):
                    self.output(line, prefixed, 4)
        return

    def output(self, line, prefixed, exit_code):
        if self.previous_line == line:
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

    def in_dictionary(self, words, dictionary):
        for word in words:
            if word in dictionary:
                return True
        return False


def main():
    parse_arguments()
    git_diff = GitDiff()
    if Config.parseInput or select.select([sys.stdin, ], [], [], 0.0)[0]:
        WarningsSupressor(git_diff).run()
    else:
        LineLengthLimit(git_diff).run()
    sys.exit(Config.exitCode)


if __name__ == '__main__':
    main()