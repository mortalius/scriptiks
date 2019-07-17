#!/bin/bash
unset AWS_PROFILE
unset AWS_DEFAULT_REGION

PROFILE=$1
REGION=$(aws --profile $PROFILE configure get region)
REGION=${REGION:-us-east-1}

echo export AWS_PROFILE=${PROFILE}
export AWS_PROFILE=${PROFILE}
echo export AWS_DEFAULT_REGION=${REGION}
export AWS_DEFAULT_REGION=${REGION}

echo Checkin\'
aws sts get-caller-identity --output text 2>/dev/null
if [ ! $? -eq 0 ]; then
    printf "\033[31m%-13s\033[0m %s\n" "ERROR: Wrong profile!"
    unset AWS_PROFILE
    unset AWS_DEFAULT_REGION
else
    aws iam list-account-aliases --output text
    echo !!! Make sure to SOURCE this script !!!
fi