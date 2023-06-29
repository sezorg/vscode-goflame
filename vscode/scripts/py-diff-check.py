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


class GitDiff:
    def __init__(self):
        self.data = {}
        config = Shell(['git', 'diff'])
        if not config.succed():
            fatal('Unable to run \'git diff\' on project')
        text = io.StringIO(config.stdout)
        patch_set = unidiff.PatchSet(text)
        self.change_list = []
        for patched_file in patch_set:
            deleted_lines = [line.target_line_no
                             for hunk in patched_file for line in hunk
                             if line.is_added and
                             line.value.strip() != '']
            appended_lines = [line.source_line_no for hunk in patched_file
                              for line in hunk if line.is_removed and
                              line.value.strip() != '']
            file_path = patched_file.path
            self.change_list.append((file_path, deleted_lines, appended_lines))
        return


class GitPatchSet:
    def __init__(self, git_diff):
        self.patched_files = []
        for change_set in git_diff.change_list:
            self.patched_files.append(GitPatchedFile(change_set))
        return


class GitPatchedFile:
    def __init__(self, change_set):
        debug(f'{change_set}')
        self.file_path = change_set[0]
        text = []
        with open(self.file_path, encoding="utf-8") as handle:
            text = handle.readlines()
        self.appended_lines = []
        for line_no in change_set[1]:
            self.appended_lines.append((line_no, text[line_no-1]))
        self.deleted_lines = []
        for line_no in change_set[2]:
            self.deleted_lines.append((line_no, text[line_no-1]))
        debug(f'appended_lines={self.appended_lines}')
        debug(f'deleted_lines={self.deleted_lines}')
        return


class GitPatchLines:
    def __init__(self, git_diff):
        self.patched_lines = {}
        for change_set in git_diff.change_list:
            file_path = change_set[0]
            for line_no in change_set[1]:
                key = f'{file_path}:{line_no}:'
                self.patched_lines[key] = True
        return

    def get(self):
        return self.patched_lines


class LineLengthLimit:
    def __init__(self, git_diff):
        self.git_diff = git_diff
        return

    def run(self):
        for patched_file in GitPatchSet(self.git_diff).patched_files:
            for line_info in patched_file.appended_lines:
                line = line_info[1].rstrip('\r\n').expandtabs(Config.tabWidth)
                length = len(line)
                if length > Config.lineLengthLimit:
                    prefix = f'{patched_file.file_path}:{line_info[0]}: '
                    spacer = ' '*(length-1)
                    print(f'{prefix}Maximum line length exceeded '
                          f'({length} > {Config.lineLengthLimit})')
                    print(f'{prefix}{line}')
                    print(f'{prefix}{spacer}^')
                    Config.exitCode = 1
        return


class WarningsSupressor:
    def __init__(self, git_diff):
        self.git_diff = git_diff
        return

    def run(self):
        identifiers = Config.excludeList.split(',')
        debug(f'supression list={identifiers}')
        supress_list = {}
        for identifier in identifiers:
            supress_list[identifier] = True
        patched_lines = GitPatchLines(self.git_diff).get()
        input_lines = sys.stdin.readlines()

        for line in input_lines:
            words = line.split()
            for word in words:
                match = re.match(r'([^:]*):([^:]*):([^:]*):', word)
                if match:
                    words.append(f'{match.group(1)}:{match.group(2)}')
            if self.in_dictionary(words, patched_lines):
                print(f'{line}')
                Config.exitCode = 1
            elif not self.in_dictionary(words, supress_list):
                print(f'{line}')
                Config.exitCode = 2
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
