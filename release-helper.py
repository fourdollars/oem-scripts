#!/usr/bin/python3
# Copyright 2021 Canonical
# Helper to release image

import sys
import argparse
import requests
import json

url="http://f1.cctu.space:5000"
pdu_req="/pdu?"
query_req="/q?"

class Platform:
    tag = ""
    skus = []
    class SKU:
        name = ""
        mac = ""
        ip = ""
        fram = ""
        pdu_port = ""
        def __init__(self, name):
            self.name = name
    def __init__(self, tag):
        self.tag = tag
    def add_sku(self, name):
        self.skus.append(self.SKU(name))
    def update_name(self, name, new_name):
        for sku in self.skus:
            if name == sku.name:
                sku.name = new_name
    def update_mac(self, name, mac):
        for sku in self.skus:
            if name == sku.name:
                sku.mac = mac
    def update_ip(self, name, ip):
        for sku in self.skus:
            if name == sku.name:
                sku.ip = ip
    def update_fram(self, name, fram):
        for sku in self.skus:
            if name == sku.name:
                sku.fram = fram
    def update_pdu_port(self, name, pdu_port):
        for sku in self.skus:
            if name == sku.name:
                sku.pdu_port = pdu_port
    def list_skus(self):
        print("[%s]" % self.tag)
        for sku in self.skus:
            print("* %s:" % sku.name)
            print(" - mac: %s" % sku.mac)
            print(" - ip: %s" % sku.ip)
            print(" - fram: %s" % sku.fram)
            print(" - pdu_port: %s" % sku.pdu_port)

def check_connection(url):
    try:
        r = requests.head(url)
    except:
        print("Not able to connect to %s" % url)
        sys.exit("Please check the network connection, e.g. VPN.")
    return r.status_code

def get_platform_information(url, platform_tag):
    p = Platform(platform_tag)

    # Get the SKUs of a platform
    tag_param = {'db': 'tag'}
    try:
        r = requests.get(url + query_req, params = tag_param)
        jr = r.json()
        for key in jr:
            if (jr[key] == platform_tag):
                p.add_sku(key)
    except:
        print("Not able to get %s from %s%s with %s." % \
                (platform_tag, url, query_req, tag_param))
        sys.exit("Please make sure the arguments are expected.")

    # Get the IP and non-force-uppercase name of each SKU
    ipo_param = {'db': 'ipo'}
    try:
        r = requests.get(url + query_req, params = ipo_param)
        jr = r.json()
        # FIXME: HIC shouldn't translate to uppercase
        # https://chat.canonical.com/canonical/pl/us55dkuarjgy3j1eko65jn49ny
        for sku in p.skus:
            cid = sku.name[-12:]
            for key in jr:
                if cid in key:
                    p.update_name(sku.name, key)
                    p.update_ip(sku.name, jr[key][0])
            if sku.ip == None:
                p.update_ip(sku.name, "offline")
    except:
        print("Not able to get %s%s from %s%s with %s." % \
                (platform_tag, url, query_req, ipo_param))
        sys.exit("Please make sure the arguments are expected.")

    # Get the MAC address of each SKU
    ipq_param = {'db': 'ipq'}
    try:
        r = requests.get(url + query_req, params = ipq_param)
        jr = r.json()
        for sku in p.skus:
            for key in jr:
                if jr[key] == sku.name:
                    p.update_mac(sku.name, key)
    except:
        print("Not able to get %s from %s%s with %s." % \
                (platform_tag, url, query_req, ipq_param))
        sys.exit("Please make sure the arguments are expected.")

    # Get the fram and PDU port number for each SKU
    for sku in p.skus:
        pdu_param = {'sku': sku.name}
        try:
            r = requests.get(url + pdu_req, params = pdu_param)
            fram = r.text.split(':')[0]
            pdu_port = r.text.split(':')[1]
            p.update_fram(sku.name, fram)
            p.update_pdu_port(sku.name, pdu_port)
        except:
            print("Not able to get %s%s from %s%s with %s." % \
                    (platform_tag, url, pdu_req, pdu_param))
            sys.exit("Please make sure the arguments are expected.")

    return p

if __name__ == "__main__":
    description = """A helper to manage the targeted SKUs of a specific
    platform."""
    help = """release-helper ${platform-tag} to manage the daily operation."""

    parser = argparse.ArgumentParser(
        description=description,
        epilog=help,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("-t", "--tag", help="The platform tag.")

    args = parser.parse_args()
    if args.tag == None:
        parser.error("Must need to specify a platform tag.")

    check_connection(url)

    p = get_platform_information(url, args.tag)

    p.list_skus()
