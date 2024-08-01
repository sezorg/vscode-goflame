#!/usr/bin/env python3

# SSH-Bench
# v 0.1 by TwoGate inc. https://twogate.com
# MIT license

# A benchmarking script for ssh.
# Tests in various ssh ciphers, MACs, key exchange algorithms.
# You can change settings in "configuration section" in this file.
# Note that result csv file will be overwrote if already exists.
# more details on: https://blog.twogate.com/entry/2020/07/30/073946

# original script downloaded from:
# https://blog.twogate.com/entry/2020/07/30/benchmarking-ssh-connection-what-is-the-fastest-cipher

import subprocess
import argparse
import time
import os
import csv

parser = argparse.ArgumentParser()
parser.add_argument("host", type=str,
                    help="hostname")
args = parser.parse_args()

host = "root@" + args.host

#### configuration section ######
# a reason of disabling compression:
#     you can't test with compression enabled.
#     transferred data is absolutly random (high entropy) which can't be compressed.
# a reason of using scp:
#     yes i know that scp is outdated today, but sftp is complex to use from programs.
#     rsync can't write out to /dev/null. that's why i use scp.
transfer_file = "/tmp/ssh-bench-random-data"
ssh_auth = ["sshpass", "-p", "root"]

ssh_command_prefix = ssh_auth + ["ssh",
                                 "-o", "StrictHostKeyChecking=no",
                                 "-o", "ControlMaster=no",
                                 "-o", "ControlPath=none",
                                 "-o", "Compression=no"]
ssh_command_suffix = [host, ":"]
scp_command_prefix = ssh_auth + ["scp",
                                 "-o", "StrictHostKeyChecking=no",
                                 "-o", "ControlMaster=no",
                                 "-o", "ControlPath=none",
                                 "-o", "Compression=no"]
scp_command_suffix = [transfer_file, f"{host}:/dev/null"]
scp_recv_command_suffix = [f"{host}:{transfer_file}", "/dev/null"]
transfer_bytes = 1024 * 1024 * 100
# transfer_bytes = 1024
##### END of configuration section #####

ciphers = subprocess.check_output(ssh_auth + ["ssh", "-Q", "cipher"]).splitlines()
macs = subprocess.check_output(ssh_auth + ["ssh", "-Q", "mac"]).splitlines()
kexes = subprocess.check_output(ssh_auth + ["ssh", "-Q", "kex"]).splitlines()
invalid_time = -1


def test_kex():
    print("Testing KexAlgorithms...")
    results = []
    for kex in kexes:
        kex_u = kex.decode('utf8')
        print(f"***** trying kex algorithm: {kex_u} *****")
        start = time.time()
        result = subprocess.run(
            ssh_command_prefix + ["-o", f"KexAlgorithms={kex_u}"] + ssh_command_suffix, check=False)
        elapsed_time = time.time() - start
        if result.returncode == 0:
            print(elapsed_time)
            results.append({"algo": kex_u, "time": elapsed_time, "success": True})
        else:
            results.append({"algo": kex_u, "time": invalid_time, "success": False})
    return results


def test_mac(receive=False):
    print("Testing MACs...")
    results = []
    for mac in macs:
        mac_u = mac.decode('utf8')
        print(f"***** trying mac algorithm: {mac_u} *****")
        start = time.time()
        if receive:
            suffix = scp_recv_command_suffix
        else:
            suffix = scp_command_suffix
        result = subprocess.run(
            scp_command_prefix + ["-o", "Ciphers=aes256-ctr", "-o", f"Macs={mac_u} "] + suffix,
            check=False)
        elapsed_time = time.time() - start
        if result.returncode == 0:
            results.append({"algo": mac_u, "time": elapsed_time, "success": True})
        else:
            results.append({"algo": mac_u, "time": invalid_time, "success": False})
    return results


def test_cipher(receive=False):
    print("Testing Ciphers...")
    results = []
    for cip in ciphers:
        cip_u = cip.decode('utf8')
        print(f"***** trying cipher: {cip_u} *****")
        start = time.time()
        if receive:
            suffix = scp_recv_command_suffix
        else:
            suffix = scp_command_suffix
        result = subprocess.run(
            scp_command_prefix + ["-o", f"Ciphers={cip_u} "] + suffix, check=False)
        elapsed_time = time.time() - start
        if result.returncode == 0:
            results.append({"algo": cip_u, "time": elapsed_time, "success": True})
        else:
            results.append({"algo": cip_u, "time": invalid_time, "success": False})
    return results


def output_as_tsv(result_type, results):
    print("")
    print(f"***** {result_type} results *****")
    results = sorted(results, key=lambda x: x['time'])
    items = []
    with open(f'./ssh-bench-{result_type}.csv', 'w', encoding='utf8') as f:
        writer = csv.writer(f)
        writer.writerow(['algorithm', 'time'])
        for entry in results:
            if entry['success']:
                writer.writerow([entry['algo'], entry['time']])
                print(f"       {entry['algo']}: {entry['time']}")
                items += [entry['algo']]
    items_text = ",".join(items)
    print(f" {result_type} list: {items_text}")


def raise_error():
    raise ValueError('Failed')


kex_result = test_kex()
print("Generating random data file...")
rand_result = os.system(f"head -c {transfer_bytes} </dev/urandom >{transfer_file}")
if rand_result != 0:
    raise_error()
mac_result = test_mac()
cipher_result = test_cipher()
print("Generating random data file at remote host...")
rand_result = os.system(
    " ".join(ssh_auth) + f" ssh {host} \"head -c {transfer_bytes} </dev/urandom >{transfer_file}\"")
if rand_result != 0:
    raise_error()
mac_r_result = test_mac(True)
cipher_r_result = test_cipher(True)

output_as_tsv("kex", kex_result)
output_as_tsv("cipher-send", cipher_result)
output_as_tsv("cipher-receive", cipher_r_result)
output_as_tsv("mac-send", mac_result)
output_as_tsv("mac-receive", mac_r_result)
