#!/usr/bin/env python
# -*- coding: utf-8 -*-

import boto3
from botocore.exceptions import ClientError
import base64
import re
import argparse

# Defaults
PROFILE = None
REGION = 'us-east-1'
SECRET_PROPERTIES_FILE = 'secret_properties.list'


def encrypt_secrets(properties_file_unencrypted, properties_file_encrypted, properties_list_file, kms_cmk):
    secret_properties = []
    with open(properties_list_file, 'r') as file:
        for property in file:
            secret_properties.append(property.strip())

    with open(properties_file_unencrypted, 'r') as file_src:
        with open(properties_file_encrypted, 'w') as file_dst:
            for line in file_src:
                # Check if line matches regex $property=$value
                # with or without whitespaces around equal sign (=)
                # Encrypt value if property is in secret_properties
                line_dst = line
                if re.match(r'[\w\.]+\s*=\s*.+', line):
                    match = re.findall(r'([\w\.]+)(\s*=\s*)(.+)[\r\n]?', line)[0]
                    key = match[0]
                    span = match[1]
                    value = match[2]
                    if key in secret_properties:
                        try:
                            ciphered_value = kms.encrypt(KeyId=kms_cmk, Plaintext=value)['CiphertextBlob']
                        except ClientError as e:
                            print "Error occured:\n%s" % e
                            return
                        b64ciphered_value = base64.b64encode(ciphered_value)
                        encrypted_line = "%s%s<CRYPT>%s</CRYPT>\n" % (key, span, b64ciphered_value)
                        line_dst = encrypted_line
                file_dst.write(line_dst)


def decrypt_secrets(properties_file_encrypted, properties_file_unencrypted, properties_list_file):
    secret_properties = []
    with open(properties_list_file, 'r') as file:
        for property in file:
            secret_properties.append(property.strip())

    with open(properties_file_encrypted, 'r') as file_src:
        with open(properties_file_unencrypted, 'w') as file_dst:
            for line in file_src:
                # Check if line matches regex $property=<CRYPT>$value</CRYPT>
                # with or without whitespaces around equal sign (=)
                # Decrypt value if property is in secret_properties
                line_dst = line
                if re.match(r'[\w\.]+\s*=\s*<CRYPT>.+</CRYPT>', line):
                    match = re.findall(r'([\w\.]+)(\s*=\s*)<CRYPT>(.+)</CRYPT>', line)[0]
                    key = match[0]
                    span = match[1]
                    b64value = match[2]
                    if key in secret_properties:
                        ciphered_value = base64.b64decode(b64value)
                        try:
                            value = kms.decrypt(CiphertextBlob=ciphered_value)['Plaintext']
                        except ClientError as e:
                            print "Error occured:\n%s" % e
                            return
                        decrypted_line = "%s%s%s\n" % (key, span, value)
                        line_dst = decrypted_line
                file_dst.write(line_dst)


def encrypt_value(value, kms_cmk):
    try:
        ciphered_value = kms.encrypt(KeyId=kms_cmk, Plaintext=value)['CiphertextBlob']
    except ClientError as e:
        print "Error occured trying to encrypt value:\n%s" % e
        return
    b64ciphered_value = base64.b64encode(ciphered_value)
    wrapped = "<CRYPT>%s</CRYPT>\n" % (b64ciphered_value)
    print('\nHash\t\t%s\n' % (wrapped))


if __name__ == '__main__':

    parser = argparse.ArgumentParser()

    subparsers = parser.add_subparsers(help='')

    parser.add_argument("--profile", required=False, default=PROFILE, type=str,
                        help="awscli profile to use")
    parser.add_argument("--region", required=False, default=REGION, type=str,
                        help="AWS region (Optional, but required if --profile is specified) ")
    parser.add_argument("--custom-list", required=False, default=SECRET_PROPERTIES_FILE, type=str,
                        help="File with list of keys. Values of these keys will be encrypted")

    # Encrypt subparser
    encrypt_parser = subparsers.add_parser('encrypt', help='Encrypts values in <infile> of those keys, that listed'
                                           ' in \'secret_properties.list\' file and saves output to <outfile>\n'
                                           'OR\n'
                                           'Encypts value provided in --value option and outputs encrypted hash')
    encrypt_parser.set_defaults(command='encrypt')

    encrypt_parser.add_argument("--key", required=True, type=str, metavar="<kms_key_arn>",
                                help="AWS KMS KeyID (key arn/alias arn)")
    encrypt_parser.add_argument("--infile", required=False, type=str, metavar="<infile>",
                                help="Source file")
    encrypt_parser.add_argument("--outfile", required=False, type=str, metavar="<outfile>",
                                help="Target file")
    encrypt_parser.add_argument("--value", required=False, type=str, metavar="<value>",
                                help="Value to encrypt")

    # Decrypt subparser
    decrypt_parser = subparsers.add_parser('decrypt', help='Decrypts all encrypted values in <infile> and saves output to <outfile>')
    decrypt_parser.set_defaults(command='decrypt')

    decrypt_parser.add_argument("--infile", required=True, type=str, metavar="<outfile>",
                                help="Source file")
    decrypt_parser.add_argument("--outfile", required=True, type=str, metavar="<outfile>",
                                help="Target file")

    args = parser.parse_args()

    profile = args.profile
    region = args.region
    custom_list = args.custom_list

    session = boto3.Session(profile_name=profile, region_name=region)
    kms = session.client('kms')

    if args.command in ['encrypt', 'decrypt']:
        print "%-15s %s" % ('Profile', profile)
        print "%-15s %s" % ('Region', region)
        print "%-15s %s" % ('SecretKeysList', custom_list)

    if args.command in 'encrypt':
        kms_cmk = args.key
        print "%-15s %s" % ('kms_cmk', kms_cmk)
        if args.value:
            value = args.value
            print "%-15s %s" % ('Value', value)
            encrypt_value(value, kms_cmk)
        elif args.infile and args.outfile:
            infile = args.infile
            outfile = args.outfile            
            print "%-15s %s" % ('Infile', infile)
            print "%-15s %s" % ('Outfile', outfile)
            encrypt_secrets(infile, outfile, custom_list, kms_cmk)    
        else:
            print('Not enough arguments.\n'
                  '\tUse --value <value> to get encrypted hash of value\n'
                  '\tUse --infile <infile> and --outfile <outfile> to encrypt properties in file\n')

    if args.command in 'decrypt':
        infile = args.infile
        outfile = args.outfile
        print "%-15s %s" % ('Infile', infile)
        print "%-15s %s" % ('Outfile', outfile)
        decrypt_secrets(infile, outfile, custom_list)
