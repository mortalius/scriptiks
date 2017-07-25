Secrets Encrypter
=================

Encrypts values in a key-value config file using Amazon KMS service.

## Usage
Encrypt file
```
./secrets_encrypter.py [--region REGION] [--profile PROFILE] [--custom-list CUSTOM_LIST] 
                       encrypt --key <kms_key_arn> --infile <plaintext_file> --outfile <encrypted_file>
```
Encrypt single value
```
./secrets_encrypter.py [--region REGION] [--profile PROFILE] [--custom-list CUSTOM_LIST]
                       encrypt --key <kms_key_arn> --value <value>
```
Decrypt file
```
./secrets_encrypter.py [--region REGION] [--profile PROFILE] [--custom-list CUSTOM_LIST]
                       decrypt --infile <encrypted_file> --outfile <plaintext_file>
```
