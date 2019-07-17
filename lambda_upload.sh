#!/bin/bash
set -e
lambda_archive="lambda_bundle.zip"
zip_targets="main.py"
pip_additional_modules="psutil redis==2.10.6"

PROFILE="default"
REGION="eu-west-1"

FUNCTION_NAME="myfunction"
HANDLER="main.lambda_handler"
ROLE="arn:aws:iam::<account_id>:role/lambda_allow_something"
DESCRIPTION=""
ENVIRONMENT="Variables={REGION=eu-west-1, ENV=dev}"
VPC_CONFIG="SubnetIds=subnet-d06a71bd,SecurityGroupIds=sg-869e6ef3"
TIMEOUT=300
MEMORYSIZE=1536

# Defines the concurrent execution limit on Lambda function. Leave blank for unlimited
CONCURRENCY_LIMIT=15  

TAGS='Project="X-Cube",cost="Xtra",Description="Save Humanity"'


function preps {
  # add required pip modules to package. update permissions to world-readable
  cp -r $zip_targets /tmp/
  cd /tmp
  pip install $pip_additional_modules -t .
  chmod -R 755 $zip_targets $pip_additional_modules
  rm -f $lambda_archive
  zip -r $lambda_archive $zip_targets $pip_additional_modules
  # cleanup
  for mdl in $pip_additional_modules; do
    rm -rf /tmp/${mdl}*
  done
  cd /tmp && rm -rf $zip_targets
}

function lambda_update_conf {
  [[ ! -z $VPC_CONFIG ]] && VPC_CONFIG_OPTION="--vpc-config $VPC_CONFIG"
  [[ ! -z $DESCRIPTION ]] && DESCRIPTION_OPTION="--description $DESCRIPTION"
  [[ ! -z $ENVIRONMENT ]] && ENVIRONMENT_OPTION="--environment $ENVIRONMENT"
  echo "Updating configuration for $FUNCTION_NAME"
  aws --profile $PROFILE --region $REGION lambda \
      update-function-configuration --function-name $FUNCTION_NAME --role $ROLE --handler $HANDLER \
                                    --timeout $TIMEOUT --memory-size $MEMORYSIZE \
                                    "$DESCRIPTION_OPTION" \
                                    "$ENVIRONMENT_OPTION" \
                                    "$VPC_CONFIG_OPTION"
}

function lambda_update_code {
    echo "Updating code for $FUNCTION_NAME"
    aws --profile $PROFILE --region $REGION lambda update-function-code --function $FUNCTION_NAME --zip-file fileb://$lambda_archive  
}

function lambda_delete {
    echo "Deleting $FUNCTION_NAME"
    aws --profile $PROFILE --region $REGION lambda delete-function --function $FUNCTION_NAME
}

function lambda_create {
    [[ ! -z $VPC_CONFIG ]] && VPC_CONFIG_OPTION="--vpc-config $VPC_CONFIG"
    [[ ! -z $DESCRIPTION ]] && DESCRIPTION_OPTION="--description $DESCRIPTION"
    [[ ! -z $ENVIRONMENT ]] && ENVIRONMENT_OPTION="--environment $ENVIRONMENT"
    echo "Creating $FUNCTION_NAME"
    aws --profile $PROFILE --region $REGION lambda create-function --function $FUNCTION_NAME --runtime python2.7 \
                               --role "$ROLE" \
                               --handler "$HANDLER" \
                               --zip-file fileb://$lambda_archive \
                               --timeout $TIMEOUT --memory-size $MEMORYSIZE \
                               "$DESCRIPTION_OPTION" \
                               "$ENVIRONMENT_OPTION" \
                               "$VPC_CONFIG_OPTION"
}

function lambda_tag {
      FUNCTION_ARN=$(aws --profile hmhdublindev lambda get-function \
                       --function-name $FUNCTION_NAME --query Configuration.FunctionArn --output text)
    echo $FUNCTION_ARN
    exit 0
    aws --profile $PROFILE --output json --region $REGION lambda tag-resource \
        --resource "$FUNCTION_ARN" \
        --tags "$TAGS"
}

function set_concurrency_limit {
  if [[ ! -z $CONCURRENCY_LIMIT ]]; then
    aws lambda put-function-concurrency --function-name $FUNCTION_NAME \
                                        --reserved-concurrent-executions $CONCURRENCY_LIMIT
  else
    aws lambda delete-function-concurrency --function-name $FUNCTION_NAME
  fi
}


if [ "$1" == "update_code" ]; then
    preps
    lambda_update_code
elif [ "$1" == "delete" ]; then
    lambda_delete
elif [ "$1" == "update_conf" ]; then
    lambda_update_conf
    set_concurrency_limit
elif [ "$1" == "create" ]; then
    preps
    lambda_create
    set_concurrency_limit
elif [ "$1" == "recreate" ]; then
    preps
    lambda_delete
    lambda_create
    set_concurrency_limit
elif [ "$1" == "tag" ]; then
    lambda_tag
else
  cat <<EOF
usage: $0 <action>
Possible actions: create
                  update
                  delete
                  recreate
                  tag
EOF
fi