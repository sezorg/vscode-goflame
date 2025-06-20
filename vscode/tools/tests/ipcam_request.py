#!/usr/bin/env python3
# Copyright 2023 RnD Center "ELVEES", JSC

import argparse
import base64
import datetime
import hashlib
import json
import logging
import os
import sys
import uuid

import requests
import warnings

warnings.filterwarnings("ignore", category=DeprecationWarning)

os.environ.pop("http_proxy", None)

def execute(args):
    execute_soap(args) if args.soap else execute_jsonrpc(args)


def create_password_digest(password):
    nonce = os.urandom(16)
    timestamp = datetime.datetime.utcnow()
    timestamp = timestamp.replace(tzinfo=datetime.timezone.utc, microsecond=0).isoformat()
    digest = base64.b64encode(
        hashlib.sha1(nonce + timestamp.encode("utf-8") + password.encode("utf-8")).digest()
    ).decode("ascii")

    return digest, base64.b64encode(nonce).decode("utf-8"), timestamp


def generate_cookies(user, password):
    pwd, nonce, created = create_password_digest(password)
    cookies = {
        "Created": created,
        "PasswordDigest": pwd,
        "Username": user,
        "Nonce": nonce,
    }
    return cookies

def execute_jsonrpc(args):
    url = f"http://{args.address}"
    endpoints = {
        "login": f"{url}/api/v2/login",
        "device": f"{url}/api/v2/devicemgmt",
        "analytics": f"{url}/api/v2/analytics",
        "media2": f"{url}/api/v2/media2",
        "media": f"{url}/api/v2/media",
        "imaging": f"{url}/api/v2/imaging",
        "actionengine": f"{url}/api/v2/actionengine",
        "ptz": f"{url}/api/v2/ptz",
        "backup": f"{url}/onvif/backup",
        "recording": f"{url}/onvif/recording",
        "schedule": f"{url}/onvif/schedule",
        "security": f"{url}/onvif/security",
        "event": f"{url}/onvif/event",
        "storagecontrol": f"{url}/api/v2/storagecontrol",
        "appmgmt": f"{url}/api/v2/appmgmt",
    }
    cookies = generate_cookies(args.user, args.password)
    session = requests.session()

    def send(url, method, params=None):
        load = {
            "jsonrpc": "2.0",
            "method": method,
            "id": str(uuid.uuid4()),
        }
        load.update({"params": json.loads(params)})
        return session.post(url, json=load, cookies=cookies)

    for k, v in cookies.items():
        session.cookies[k] = v

    session.headers.update({"Content-Type": "application/json"})

    if args.load:
        r = send(endpoints[args.service], args.command, args.load)
    elif args.jsonfile:
        with open(args.jsonfile) as f:
            load = f.read()
            r = send(endpoints[args.service], args.command, load)
    else:
        r = send(endpoints[args.service], args.command, "{}")
    print(r.text)


def execute_soap(args):
    try:
        from onvif import ONVIFCamera
    except ImportError:
        print("No module named 'onvif'. You need to install onvif_zeep.")
        print(ZEEP_HELP)
        sys.exit(1)

    cam = ONVIFCamera(args.address, args.port, args.user, args.password)

    if args.service == "device":
        args.service = "devicemgmt"
    else:
        getattr(cam, f"create_{args.service}_service")()

    service = getattr(cam, args.service)
    request_function = getattr(service, args.command)

    if args.debug:
        log = logging.getLogger("zeep.transports")
        log.setLevel(logging.DEBUG)

    if args.load:
        res = request_function(json.loads(args.load))
    elif args.jsonfile:
        with open(args.jsonfile) as f:
            load = f.read()
            res = request_function(json.loads(load))
    else:
        res = request_function({})
    print(res)


EPILOG = """
Script output is a raw JSON string without formatting or prettifying.
Use third party tools to format and prettify.\n\n

It is strongly recommended to use jq tool [1] for formatting and processing output JSON.
For example:
   ipcam_request.py -a <hostname> -s <service> -c <request> | jq

[1] https://github.com/stedolan/jq
"""


ZEEP_HELP = """
To send command via SOAP you need to install onvif_zeep package.
To install for user:
    python3 -m pip install --user onvif_zeep
To install in virtualenv:
    python3 -m venv .venv && source .venv/bin/activate && python3 -m pip install onvif_zeep
"""


def main():
    parser = argparse.ArgumentParser(
        add_help=True,
        formatter_class=argparse.RawTextHelpFormatter,
        description="Tool for sending requests to IPCAM via JSON-RPC or SOAP",
        epilog=EPILOG,
    )
    parser.add_argument("-a", "--address", required=True, help="IP-address or hostname")
    parser.add_argument("-P", "--port", default=80, help="Port")
    parser.add_argument(
        "-s",
        "--service",
        required=True,
        help="Services: device, analytics, media, media2, imaging, actionengine, ptz and others",
    )
    parser.add_argument("-c", "--command", required=True, help="ONVIF command")
    parser.add_argument(
        "-l",
        "--load",
        help="""Parameters for ONVIF command, e.g.
        -l '{"ProfileToken": "Main", "ConfigurationToken": "main"}""",
    )
    parser.add_argument("-f", "--jsonfile", help="Read command parameters from json file")
    parser.add_argument("-u", "--user", default="admin", help="Username")
    parser.add_argument("-p", "--password", default="admin", help="Password")
    parser.add_argument(
        "-S",
        "--soap",
        action="store_true",
        help="Use SOAP protocol for request (default protocol is JSON-RPC)",
    )
    parser.add_argument(
        "-d", "--debug", action="store_true", help="Print debug logs for SOAP transport"
    )
    args, _ = parser.parse_known_args()
    execute(args)


if __name__ == "__main__":
    main()
