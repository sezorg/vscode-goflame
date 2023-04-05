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

def parseArgsuments():
	parser = argparse.ArgumentParser(
		prog = os.path.basename(__file__),
		description = 'Update Gerrit Git tags & branches',
		epilog = 'Update Gerrit Git tags & branches'
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
	config = parser.parse_args()
	config.exitCode = 0
	config.warnCount = 0
	return config

def debug(message):
	#print(f'VERBOSE: {config}')
	if config.debug > 0:
		print(f'DEBUG: {message}')

def verbose(message):
	#print(f'VERBOSE: {config}')
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

class Shell(object): 
	def __init__(self, params):
		self.params = params
		proc = subprocess.Popen(
			params, 
			shell=True, 
			stdout=subprocess.PIPE, 
			stderr=subprocess.PIPE)
		self.stdout, self.stderr = proc.communicate()
		self.status = proc.returncode
		return

	def succeeded(self):
		return self.status == 0

	def debug(self):
		debug(f'Shell params: {self.params}')
		debug(f"Shell stdout: {self.stdout}")
		debug(f'Shell stderr: {self.stderr}')
		debug(f'Shell status: {self.status}, succeded {self.succeeded()}')
		return

class GitConfig(object):
	def __init__(self):
		config = Shell(['git', 'status'])
		config.debug()
		return

class GerritTags(object):
	def __init__(self):
		return
    
	def readGitConfig():
		return

def main():
    # list
    #result = Execute(['ls', '-lh'])
    #result.debug()
  
	config = parseArgsuments()
	print(config)
	gitConfig = GitConfig()

if __name__ == '__main__':
    main()

