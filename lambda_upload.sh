#!/bin/bash
lambda_archive="lambda_bundle.zip"
zip_targets="main.py requirements.txt"

handler="main.lambda_handler"
role="arn:aws:iam::<account_id>:role/lambda_allow_something"
function_name="myfunction"
description=""
environment="Variables={REGION=eu-west-1, ENV=dev}"

# workaround for possible impossibility to set file world-readable
cp $zip_targets /tmp/
cd /tmp
chmod a+r $zip_targets
rm -f $lambda_archive
zip $lambda_archive $zip_targets


if [ "$1" == "update" ]; then
    echo "Updating $function_name"
    aws lambda update-function-code --function $function_name --zip-file fileb://$lambda_archive
elif [ "$1" == "delete" ]; then
    echo "Deleting $function_name"
    aws lambda delete-function --function $function_name
else
    echo "Creating $function_name"
    aws lambda create-function --function $function_name --runtime python2.7 \
                               --role "$role" \
                               --handler "$handler" \
                               --zip-file fileb://$lambda_archive \
                               --timeout 300 --memory-size 512 \
                               --description "$description" \
                               --environment "$environment"
fi