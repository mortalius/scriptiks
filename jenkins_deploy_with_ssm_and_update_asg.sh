#!/bin/bash
set -xe

source aws_wrappers.sh
export AWS_DEFAULT_REGION="us-east-1"

# ALB_TG_NAME
# ASG_NAME
# LC_PREFIX

# 1. Get one of the instances from TG
INSTANCE_LIST=($(get_registered_instances_from_alb_tg $ALB_TG_NAME))
INSTANCE_ID=${INSTANCE_LIST[0]}

if [ ${#INSTANCE_LIST[@]} -eq 0 ]; then
    log "No registered instances in TG: $ALB_TG_NAME. Exiting."
    exit 1
fi

# 2. Disable AS processes on AS group by InstanceId
DO_ENABLE_ASG="$(disable_autoscaling_by_instance_id $INSTANCE_ID)"


#############################################################
# 3.                        Deploy                          #
#############################################################

repo_url="https://ci-user:${ci-user-pass}@github.com/co/repo.git"
www_root="/var/www"
www_repo_dir="git/repo/www"

# !!! escape $ with backslash if variable expanding needs to take place on remote hosts
cat <<SCRIPT_HERE > deploy_script_commands
set -e
rm -vrf /tmp/repo_temp
git clone $repo_url --branch $Branch --single-branch repo_temp
echo \$?
cp -rv /tmp/repo_temp/$www_repo_dir/* $www_root
rm -rf /tmp/repo_temp
ls -
if [[ "$RestartApache" == "true" ]]; then
  echo ReStarting apache..
  service httpd restart
  [ \$? -eq 0 ] && echo "Restart success" || echo "Restart Failed"
fi

SCRIPT_HERE

#==========================

function check_send_command_status {
    aws ssm get-command-invocation --command-id="$command_id" --instance-id=$1 --output text --region "$Region" --query Status
}
function get_command_standard_output {
    aws ssm get-command-invocation --command-id="$command_id" --instance-id=$1 --output text --region "$Region" --query StandardOutputContent
}
function get_command_error_output {
    aws ssm get-command-invocation --command-id="$command_id" --instance-id=$1 --output text --region "$Region" --query StandardErrorContent
}

# Format to json Hack to be able to write script clean
json_commands="[$(cat deploy_script_commands | sed -r "s/(.*)/\'\1\',/" | tr -d '\n')'']"
echo $json_commands

# Run script at remote hosts
InstanceIDs=$(echo ${INSTANCE_LIST[@]} | tr ' ' ',')

echo "Running commands on $InstanceIDs"
command_id=$(aws ssm send-command --document-name "AWS-RunShellScript" --targets "Key=instanceids,Values=$InstanceIDs" \
                                  --parameters commands="$json_commands",executionTimeout=3600,workingDirectory="/tmp" \
                                  --timeout-seconds 600 --region "$Region" \
                                  --output text --query Command.CommandId)    
echo "Command_id - $command_id"

# Wait for execute to complete and get output
for instance in $(echo $InstanceIDs | tr ',' ' '); do
    while [[ "$(check_send_command_status $instance)" == "InProgress" ]]; do
        echo "Waiting for commands execucution to complete."
        sleep 1
    done

    echo -e "==> INSTANCE ======> $instance <========================"
    echo -e "==> STANDARD OUTPUT"
    get_command_standard_output $instance
    echo -e "==> ERROR OUTPUT"
    get_command_error_output $instance
    echo -e "========================================================"
done

################################################################################

# 4. Stop instance prior to making AMI
stop_instance $INSTANCE_ID

# 5. Make AMI from Instance by ID
AMI_ID="$(create_ami_by_instance_id $INSTANCE_ID)"

# 6. Start instance (required for creating new LC from instance)
start_instance $INSTANCE_ID

# 7. Create LC from Instance
NEW_LC_NAME="$LC_PREFIX-$(date +'%y%m%d-%H-%M-%S')"
wait_for_instance_state $INSTANCE_ID "running" $START_STOP_TIMEOUT_SEC
create_lc_from_instance_with_new_ami $NEW_LC_NAME $INSTANCE_ID $AMI_ID

# 8. Update AS group with new LC
update_asg_with_lc $ASG_NAME $NEW_LC_NAME

# 9. Resume suspended processes on ASG
enable_asg $ASG_NAME $DO_ENABLE_ASG