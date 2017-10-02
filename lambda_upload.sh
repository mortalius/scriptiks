#!/bin/bash
lambda_archive="lambda_bundle.zip"
zip_targets="main.py requirements.txt"

profile="default"

handler="main.lambda_handler"
role="arn:aws:iam::<account_id>:role/lambda_allow_something"
function_name="myfunction"
description=""
environment="Variables={REGION=eu-west-1, ENV=dev}"

# workaround for possible impossibility to set file world-readable
function preps {
  cp $zip_targets /tmp/
  cd /tmp
  chmod a+r $zip_targets
  rm -f $lambda_archive
  zip $lambda_archive $zip_targets
}

function lambda_update {
    echo "Updating $function_name"
    aws --profile $profile lambda update-function-code --function $function_name --zip-file fileb://$lambda_archive  
}
function lambda_delete {
    echo "Deleting $function_name"
    aws --profile $profile lambda delete-function --function $function_name
}
function lambda_create {
    echo "Creating $function_name"
    aws --profile $profile lambda create-function --function $function_name --runtime python2.7 \
                               --role "$role" \
                               --handler "$handler" \
                               --zip-file fileb://$lambda_archive \
                               --timeout 300 --memory-size 512 \
                               --description "$description" \
                               --environment "$environment"
}

if [ "$1" == "update" ]; then
    preps
    lambda_update
elif [ "$1" == "delete" ]; then
    preps
    lambda_delete
elif [ "$1" == "create" ]; then
    preps
    lambda_create
elif [ "$1" == "recreate" ]; then
    preps
    lambda_delete
    lambda_create
else
  cat <<EOF
usage: $0 <action>
Possible actions: create
                  update
                  delete
                  recreate
EOF
fi