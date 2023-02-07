#!/usr/bin/env python3

import argparse
import demjson
import http.client as http_client
import json
import logging
import os
import requests
import sys
import textwrap
import uuid
from zeep.wsse.username import UsernameToken

json_api_tokens = {
	'GetImagingSettings': 'imaging',
	'GetVideoSources': 'media',
	'GetSystemDateAndTime': 'device_service',
	'SetSystemDateAndTime': 'device_service',
}

# Global variables
args = { 'verbose': False }
json_url = ''
json_method = ''
json_params = {}


def error(message):
	print(f'ERROR: {message}')
	sys.exit(-1)


def verbose(message):
	if args.verbose:
		print(f'VERBOSE: {message}')


def parseArguments():
	desc = ("JSON request have a following format:\n"
		"\t---IP[:PORT][/token]/Method[JSON][:JSONFileName]\n"
		f'where:\n'
		f'	IP - ip address ov the JSON server\n'
		f'	PORT - optional port\n'
		f'	token - REST API token to be called,\n'
		)

	parser = argparse.ArgumentParser(
		prog = 'jsonrq',
		description = 'JSON request script',
		epilog = textwrap.dedent('''\
			JSON request have a following format:
			    IP[:PORT][/token]/Method[JSON][:JSONFileName]
			    exactly the way
			    I want it
			'''))
	parser.add_argument(
		'-v', '--verbose',
		action='store_true',
		help='Enable verbose mode')
	parser.add_argument(
		'request',
		metavar='Request',
		type=str,
		help='JSON Request (IP[:PORT][/token]/Method[JSON][:JSONFileName])')
	global args
	args = parser.parse_args()


def parseRequest():
	global json_url, json_method, json_params
	request_str = args.request
	verbose('request is: ' + request_str)
	request_args = request_str.split('/')
	verbose('request_args: ' + ', '.join(request_args))
	if len(request_args) == 2:
		request_args.insert(1, '')
	if len(request_args) < 3:
		error(f'Not enough paramenters in request ({len(request_args)})')
	address = request_args[0]
	del request_args[0]
	json_method = request_args[-1]
	del request_args[-1]
	separator = json_method.find('{')
	if separator >= 0:
		params = json_method[separator:]
		json_method = json_method[0:separator]
		json_params = demjson.decode(params, 'utf-8')
	else:
		separator = json_method.find(':')
		if separator >= 0:
			filename = json_method[separator+1:]
			json_method = json_method[0:separator]
			with open(filename, 'r') as file:
				params = file.read()
			json_params = demjson.decode(params, 'utf-8')
	address = address.strip()
	json_method = json_method.strip()
	if len(request_args) == 1:
		api_token = request_args[0]
		if api_token == '':
			if json_method in json_api_tokens:
				api_token = json_api_tokens[json_method]
			else:
				error(f'Unable to determine API token for {json_method} method')
		request_args = ['api', 'v2', api_token]
	api_path = '/'.join(request_args)
	json_url = f'http://{address}/{api_path}/'


def enableLogging():
	if not args.verbose:
		return
	http_client.HTTPConnection.debuglevel = 1
	logging.basicConfig()
	logging.getLogger().setLevel(logging.DEBUG)
	requests_log = logging.getLogger('requests.packages.urllib3')
	requests_log.setLevel(logging.DEBUG)
	requests_log.propagate = True


def performRequest():
	token = UsernameToken('admin', 'admin', use_digest=True)
	pwd, nonce, created = token._create_password_digest()
	cookies = {
		'Created': created.text,
		'PasswordDigest': pwd.text,
		'Username': 'admin',
		'Nonce': nonce.text,
	}
	session = requests.session()
	session.headers.update({'Content-Type': 'application/json'})
	for key, value in cookies.items():
		session.cookies[key] = value
	request_id = str(uuid.uuid4())
	request_json = {
		'jsonrpc': '2.0',
		'method': json_method,
		'id': request_id,
		'params': json_params
	}

	try:
		response = session.post(json_url, json=request_json, cookies=cookies)
	except requests.exceptions.RequestException as e:
		raise SystemExit(e)

	print(f'--- status_code: {response.status_code}; text: \'{response.text}\'')
	if response.ok and response.text != '':
		response_json = json.loads(response.text)
		print(f'--- id: {request_id}; method: {json_method}; response: {json.dumps(response_json, indent=4)}')


def main():
	parseArguments()
	parseRequest()
	enableLogging()
	verbose(f'json_url={json_url}')
	verbose(f'json_method={json_method}')
	os.environ.pop('http_proxy', None)
	performRequest()


if __name__ == '__main__':
    main()
