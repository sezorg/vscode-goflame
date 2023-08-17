#!/usr/bin/env python3

import os
import sys
import argparse
import pathlib
import subprocess

defaultChecksList = ['restrict', 'goimports', 'govet', 'staticcheck']
defaultPathsList = ['.']
defaultFilesList = []
defaultExtensList = ['*.go']
defaultLineLengthLimit = 92
defaultLineCountLimit = 1024
config = {}


def removeFromDict(dict, values):
    for value in values:
        del dict[value]


def parseArgs():
    parser = argparse.ArgumentParser(
        prog=os.path.basename(__file__),
        description='Run several tests on Go application or package',
        epilog='Run several tests on Go application or package'
    )
    parser.add_argument(
        '-c', '--check',
        metavar='CHECK',
        help=f'List of the to be performed, default {defaultChecksList}',
        required=False,
        action='append',
        type=str,
        default=[],
    )
    parser.add_argument(
        '-p', '--path',
        metavar='PATH',
        help=f'List of the paths to be processed, default {defaultPathsList}',
        required=False,
        action='append',
        type=str,
        default=[],
    )
    parser.add_argument(
        '-f', '--file',
        metavar='FILE',
        help=f'List of the files to be processed, default {defaultFilesList}',
        required=False,
        action='append',
        type=str,
        default=[],
    )
    parser.add_argument(
        '-e', '--extension',
        metavar='EXT',
        help=f'One or more extensionsions of the files to be processed, default {defaultExtensList}',
        required=False,
        action='append',
        type=str,
        default=[],
    )
    parser.add_argument(
        '-l', '--lineLengthLimit',
        metavar='NUM',
        help=f'Check for a line length limits, default {defaultLineLengthLimit} chacaters',
        required=False,
        action='store',
        type=int,
        default=defaultLineLengthLimit,
        # choices=range(0, 1024),
    )
    parser.add_argument(
        '-x', '--lineCountLimit',
        metavar='NUM',
        help=f'Check for a line count limits, default {defaultLineCountLimit} lines',
        required=False,
        action='store',
        type=int,
        default=defaultLineCountLimit,
    )
    parser.add_argument(
        '-o', '--outputLines',
        help='Emit source lines to the output',
        required=False,
        action='store_true',
        default=False,
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
    config = parser.parse_args()
    config.checkList = config.check if len(config.check) != 0 else defaultChecksList
    config.pathsList = config.path if len(config.path) != 0 else defaultPathsList
    config.filesList = config.file if len(config.file) != 0 else defaultFilesList
    config.extensionsList = config.extension if len(config.extension) != 0 else defaultExtensList
    config.exitCode = 0
    config.warnCount = 0
    removeFromDict(config.__dict__, ['check', 'path', 'file', 'extension'])
    return config


def verbose(message):
    # print(f'VERBOSE: {config}')
    if config.verbose > 0:
        print(f'VERBOSE: {message}')


def emitWarning(warningMessage):
    if not config.silent:
        print(warningMessage)
    config.warnCount += 1
    config.exitCode = 1


def emitLineWarning(lineMessage, lineText):
    if not config.silent:
        print(lineMessage)
        if config.outputLines:
            print(lineText)
    config.warnCount += 1
    config.exitCode = 1


def findFiles(path, extension):
    pattern = ''
    for c in extension:
        pattern += c if not c.isalpha() else f'[{c.upper()}{c.lower()}]'
    verbose(f'Processing extension "{extension}" pattern "{pattern}" in path "{path}" . . .')
    return list(pathlib.Path(path).rglob(pattern))


def restrictLine(fileName, lineIndex, lineText):
    lineText = lineText.rstrip()
    lineLen = len(lineText)
    if lineLen == 0:
        return
    if lineText[lineLen - 1] == '`':
        return
    if config.lineLengthLimit > 0 and lineLen > config.lineLengthLimit:
        lineWarning = f'{fileName}:{lineIndex}: Line length {lineLen} exceeds limit {config.lineLengthLimit}'
        emitLineWarning(lineWarning, lineText)


def restrictFile(fileName):
    lineIndex = 0
    fd = open(fileName, 'r')
    for lineText in fd:
        lineIndex += 1
        restrictLine(fileName, lineIndex, lineText)
    if config.lineCountLimit > 0 and lineIndex > config.lineCountLimit:
        emitWarning(f'{fileName}: Line count {lineIndex} exceeds limit {config.lineCountLimit}')


def checkRestrictions(checkId):
    verbose(f'Running "{checkId}" check')
    if config.lineLengthLimit == 0 and config.lineCountLimit == 0:
        return
    allFiles = config.filesList
    for path in config.pathsList:
        for ext in config.extensionsList:
            allFiles += findFiles(path, ext)
    allFiles = sorted(allFiles)
    verbose(f'All files: {allFiles}')
    for fileName in allFiles:
        restrictFile(fileName)


def checkGoImports(checkId):
    verbose(f'Running "{checkId}" check')
    subprocess.run(['goimports', '-d', '.'])
    return


def checkGoVet(checkId):
    subprocess.run(['go', 'vet', './...'])
    return


def checkGoStaticcheck(checkId):
    subprocess.run(['staticcheck', './...'])
    return


def main():
    global config
    config = parseArgs()
    verbose(f'Config is: {config}')

    checks = {
        'restrict': checkRestrictions,
        'goimports': checkGoImports,
        'govet': checkGoVet,
        'staticcheck': checkGoStaticcheck,
    }
    for checkId in config.checkList:
        checkProc = checks[checkId]
        if checkProc:
            verbose(f'Running "{checkId}" check')
            checkProc(checkId)
        else:
            emitWarning(f'Warning: Unknown check id "{checkId}')

    if config.exitCode != 0 and not config.silent:
        print(f'Terminating with exit code {config.exitCode}, {config.warnCount} warnings')
    sys.exit(config.exitCode)


if __name__ == '__main__':
    main()
