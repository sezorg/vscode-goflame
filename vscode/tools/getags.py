#!/usr/bin/env python3

import os
import sys
import argparse
import pathlib
import subprocess
import configparser
import re

_arguments = {}

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
	global _arguments
	_arguments = parser.parse_args()
	_arguments.exitCode = 0
	_arguments.warnCount = 0
	return

def debug(message):
	#print(f'VERBOSE: {_arguments}')
	if _arguments.debug > 0:
		print(f'DEBUG: {message}')

def verbose(message):
	#print(f'VERBOSE: {_arguments}')
	if _arguments.verbose > 0:
		print(f'VERBOSE: {message}')

def warning(message):
	print(f'WARNING: {message}')

def error(message):
	print(f'ERROR: {message}')

def filter(pattern, value):
	return re.search(pattern, value).group(0)

class Shell(object):
	def __init__(self, params):
		self.params = params
		proc = subprocess.Popen(
			params, 
			stdout=subprocess.PIPE, 
			stderr=subprocess.PIPE)
		stdout, stderr = proc.communicate()
		self.stdout = stdout.decode()
		self.stderr = stderr.decode()
		self.status = proc.returncode
		if not self.succed():
			error(f'Failed to execute: {self.params}')
		return

	def succed(self):
		return self.status == 0

	def debug(self):
		debug(f'Shell params: {self.params}')
		debug(f"Shell stdout: {self.stdout}")
		debug(f'Shell stderr: {self.stderr}')
		debug(f'Shell status: {self.status}, succed {self.succed()}')
		return

class GitConfig(object):
	def __init__(self):
		self.data = {}
		config = Shell(['git', 'config', '--list'])
		config.debug()
		if not config.succed():
			error("Unable to get Git configuration")
			return
		lines = config.stdout.split('\n')
		for line in lines:
			pos = line.find("=")
			if pos >= 0:
				key = line[0:pos]
				value = line[pos+1:]
				self.data[key] = value
				debug(f'Git configuration: key = {key} || value = {value}')
		self.userEmail = self.data['user.email']
		if self.userEmail == '':
			warning('Unable to retrieve user email from git config')
		return


class GerritTags(object):
	def __init__(self, userEmail, command):
		self.execute = true
		overallFilter = 'status:open'
		emailFilter = ''
		match command:
		case 'me':
			emailFilter = userEmail
		case 'del':
			self.execute = false
		case 'all':
			emailFilter = ''
		case _:
			emailFilter = command + filter(r'^.*(@.*)@', userEmail)
		print(emailFilter)

		return

	def readGitConfig():
		return

def main():
	parseArgsuments()
	gitConfig = GitConfig()

if __name__ == '__main__':
	main()

