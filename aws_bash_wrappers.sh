#!/bin/bash
set -e

AWS_CMD=$(which aws)

START_STOP_TIMEOUT_SEC=300

function log() {
    echo "`date +'%D %T'` : $1" 1>&2
}

function track_error() {
    if [ $1 != "0" ]; then
        log "Error occured at `date` : $2"
        exit $1
    fi
}

function get_lc_from_asg() {
    local _ASG_NAME=$1
    local _lc_name=$($AWS_CMD autoscaling describe-auto-scaling-groups --auto-scaling-group-names $_ASG_NAME \
                 --query AutoScalingGroups[0].LaunchConfigurationName --output text)
    # Function returns : Launch Configuration Name from provided ASG
    echo $_lc_name
}

function get_registered_instances_from_alb_tg() {
    # Get list of instances registered in ALB Target Group
    local _TG_NAME=$1
    
    log "Getting registered instances from ALB TG: $_TG_NAME"
    local _tg_arn="$($AWS_CMD elbv2 describe-target-groups --names $_TG_NAME --output text --query TargetGroups[0].TargetGroupArn)"
    local _tg_instance_list=$($AWS_CMD elbv2 describe-target-health --target-group-arn $_tg_arn --output text --query TargetHealthDescriptions[*].Target.Id | tr '\t' ' ' | uniq)
    log "$_tg_instance_list"
  
    # Function returns: List of instances registered in TG as "i-abcd i-1234 i-4567"
    echo $_tg_instance_list
}

function create_lc_from_instance_with_new_ami() {
  # Create new Launch Configuration based on AS instance with AMI override
  local _OLD_LC_NAME=$1
  local _NEW_LC_NAME=$2
  local _INSTANCE_ID=$3
  local _AMI_ID=$4
  # block device mapping is not specified as it should be automatically created based on new AMI bdm
  # local _lc_bdm=$($AWS_CMD autoscaling describe-launch-configurations \
  #             --launch-configuration-names $_OLD_LC_NAME \
  #             --query LaunchConfigurations[0].BlockDeviceMappings)
  # echo $_lc_bdm
  log "Creating new LaunchConfiguration from instance with new AMI"
  log "             Old LC Name:    $_OLD_LC_NAME"
  log "             New LC Name:    $_NEW_LC_NAME"
  log "             Instance:       $_INSTANCE_ID"
  log "             AMI ID:         $_AMI_ID"
  $AWS_CMD autoscaling create-launch-configuration --launch-configuration-name "$_NEW_LC_NAME" \
                                                   --instance-id "$_INSTANCE_ID" \
                                                   --image-id "$_AMI_ID"
  # --block-device-mappings "$_lc_bdm" \
}

function create_ami_by_instance_id() {
    local _INSTANCE_ID=$1
    local _instance_name=$($AWS_CMD ec2 describe-instances --instance-ids=$_INSTANCE_ID \
                                                --query 'Reservations[0].Instances[0].Tags[?Key==`Name`].Value' --output text)

    local _instance_ip=$($AWS_CMD ec2 describe-instances --instance-ids=$_INSTANCE_ID \
                                              --query Reservations[0].Instances[0].PrivateIpAddress --output text)

    # Create AMI from instance
    log "Creating AMI based on instance $_INSTANCE_ID (Name: $_instance_name) [$_instance_ip]"
    local _ami_id=$($AWS_CMD ec2 create-image --instance-id $_INSTANCE_ID --name "$_instance_name-`date +'%y%m%d-%H-%M-%S'`" \
                                        --description "AMI for $_instance_name  on `date +'%D %T'`" \
                                        --query ImageId --output text)
    track_error $? "Creating AMI from $_instance_name [$_instance_ip]"

    # Waiting until AMI complete and processing state
    until [[ "$_ami_status" =~ failed|available ]]
    do
      _ami_status="$($AWS_CMD ec2 describe-images --image-ids $_ami_id --query Images[0].State --output text)"
      log "Waiting for AMI $_ami_id to be created"
      sleep 5
    done
    
    if [[ "$_ami_status" == available ]]; then
        log "AMI $_ami_id created"
    elif [[ "$_ami_status" == failed ]]; then
        _fail_reason=$($AWS_CMD ec2 describe-images --image-ids $_ami_id --query Images[0].StateReason.Message --output text)
        log "AMI $_ami_id creation failed. Reason: $_fail_reason"
        exit 1
    fi
    track_error $? "Creating AMI from $_instance_name [$_instance_ip] (step 2)"

    # Propagating tags (except Name) from Instance to AMI and snapshots
    local _instance_tags=$($AWS_CMD ec2 describe-instances --instance-ids=$_INSTANCE_ID \
                         --query 'Reservations[0].Instances[0].Tags[?starts_with(Key,`aws:`) != `true`]|[?Key!=`Name`]')
    local _snapshot_ids=$($AWS_CMD ec2 describe-images --image-ids $_ami_id \
                                            --query 'Images[0].BlockDeviceMappings[*].Ebs.SnapshotId' --output text | tr '\t' ' ')

    if [[ "$_instance_tags" != "None" ]] && [[ "$_instance_tags" != "" ]]; then
        log "Tagging AMI $_ami_id with instance's tags: $_instance_tags"
        $AWS_CMD ec2 create-tags --resources $_ami_id --tags "$_instance_tags"
        for _id in $_snapshot_ids; do
            log "Tagging snapshot $_id with instance's tags: $_instance_tags"
            $AWS_CMD ec2 create-tags --resources $_id --tags "$_instance_tags"
        done
    else
        log "No tags found at instance $_INSTANCE_ID. AMI/Snapshot tagging skipped. "
    fi

    # Returning AMI ID 
    echo $_ami_id
}

function disable_autoscaling_by_instance_id()
{
    # Get ASG by instance id and suspend all processes
    local _INSTANCE_ID=$1
    # Get the autoscaling group data.
    local _as_group=$($AWS_CMD autoscaling describe-auto-scaling-instances \
                         --instance-id=$_INSTANCE_ID --output text \
                         --query AutoScalingInstances[0].AutoScalingGroupName)

    # Checking if Autoscaling already had processes suspended or no
    local _asg_suspended_processes=$($AWS_CMD autoscaling describe-auto-scaling-groups \
                                            --auto-scaling-group-name $_as_group --output text \
                                            --query AutoScalingGroups[0].SuspendedProcesses[*]) 

    # Checking if AS group is set up for specified instance. And if it has been already suspended.
    # If suspended, then do nothing and set _ASG_REQUIRES_ENABLING=FALSE
    # If not suspended, then do suspend and set _ASG_REQUIRES_ENABLING=TRUE
    if [ ! -z "$_as_group" ]; then
      if [ ! -z "$_asg_suspended_processes" ]; then
        log "Found suspended processes for AS Group $_as_group: \n $_asg_suspended_processes."
        log "AS Group remained intact"
        _ASG_REQUIRES_ENABLING="FALSE"
        log "Setting _ASG_REQUIRES_ENABLING=$_ASG_REQUIRES_ENABLING"
      else
        _ASG_REQUIRES_ENABLING="TRUE"
        log "Suspending all processes for AS Group $_as_group"
        $AWS_CMD autoscaling suspend-processes --auto-scaling-group-name ${_as_group}
        track_error $? "Suspending launch of new instances on the autoscaling group."
        sleep 30
        log "All process disabled on AS group ${_as_group}"
      fi
    else
      log "Instance doesn't belong to any AS group"
      _ASG_REQUIRES_ENABLING="FALSE"
      log "Setting _ASG_REQUIRES_ENABLING=$_ASG_REQUIRES_ENABLING"
    fi
    # Function returns: variable to control as group enable behavior
    echo $_ASG_REQUIRES_ENABLING
}

function update_asg_with_lc() {
    local _ASG_NAME=$1
    local _LC_NAME=$2
    # Get the autoscaling group data.
    local _as_group_exists=$($AWS_CMD autoscaling describe-auto-scaling-groups --auto-scaling-group-names $_ASG_NAME \
                                       --query AutoScalingGroups[0].AutoScalingGroupName --output text)
    # Updating ASG with new LC
    if [ ! -z $_as_group_exists ]; then
        log "Updating AS group: $_ASG_NAME with new LC: $_LC_NAME"
        $AWS_CMD autoscaling update-auto-scaling-group --auto-scaling-group-name $_ASG_NAME \
                                                       --launch-configuration-name $_LC_NAME
    else
        track_error 1 "AS group: $_ASG_NAME not found"
    fi
}

function enable_asg() {
    local _ASG_NAME=$1
    local _DO_ENABLE_FLAG=$2
    local _as_group_exists=$($AWS_CMD autoscaling describe-auto-scaling-groups --auto-scaling-group-names $_ASG_NAME \
                                       --query AutoScalingGroups[0].AutoScalingGroupName --output text)
    if [ ! -z "$_as_group_exists" ]; then
        if [ "$_DO_ENABLE_FLAG" == "TRUE" ]; then
            log "Resuming suspended processes on the AS group: $_ASG_NAME."
            $AWS_CMD autoscaling resume-processes --auto-scaling-group-name $_ASG_NAME
            track_error $? "Resuming suspended processes on the autoscaling Group $_ASG_NAME."
            log "AS group ${_ASG_NAME} enabled"
        else
            log "Leaving intact AS group processes as DO_ENABLE_FLAG set to $_DO_ENABLE_FLAG"
        fi            
    fi
}

function wait_for_instance_state() {
    # Wait until instance transit to 
    local _INSTANCE_ID=$1
    local _DESIRED_STATE=$2
    local _WAIT_TIMEOUT=$3

    local _start_seconds=$(date +'%s')
    until [[ "$_state" == "$_DESIRED_STATE" ]]
    do
      _state=$($AWS_CMD ec2 describe-instances --instance-ids=$_INSTANCE_ID \
                                          --query Reservations[0].Instances[0].State.Name --output text)
      log "Waiting for Instance $_INSTANCE_ID transition to '$_DESIRED_STATE' state"
      sleep 10
      local _now_seconds=$(date +'%s')
      if [[ $((_now_seconds - _start_seconds)) -gt $_WAIT_TIMEOUT ]]; then 
        log "It took too long for instance to transit to '$_DESIRED_STATE' state. Exiting."
        exit 1
      fi
    done
}

function stop_instance() {
    local _INSTANCE_ID=$1
    local _instance_ip=$($AWS_CMD ec2 describe-instances --instance-ids=$_INSTANCE_ID \
                                --query Reservations[0].Instances[0].PrivateIpAddress --output text)
    
    log "Stopping instance $_INSTANCE_ID [$_instance_ip]"
    $AWS_CMD ec2 stop-instances --instance-id $_INSTANCE_ID >/dev/null
    track_error $? "Stop Instance $_INSTANCE_ID [$_instance_ip]"

    wait_for_instance_state $_INSTANCE_ID "stopped" $START_STOP_TIMEOUT_SEC
    track_error $? "Stop Instance $_INSTANCE_ID [$_instance_ip] timeout "

    log "Instance $_INSTANCE_ID stopped"
}

function start_instance() {
    local _INSTANCE_ID=$1
    local _instance_ip=$($AWS_CMD ec2 describe-instances --instance-ids=$_INSTANCE_ID \
                                --query Reservations[0].Instances[0].PrivateIpAddress --output text)
    log "Starting instance $_INSTANCE_ID [$_instance_ip]"
    
    $AWS_CMD ec2 start-instances --instance-ids $_INSTANCE_ID >/dev/null
    track_error $? "Starting Instance $_INSTANCE_ID [$_instance_ip]"

    wait_for_instance_state $_INSTANCE_ID "running" $START_STOP_TIMEOUT_SEC
    track_error $? "Starting Instance $_INSTANCE_ID [$_instance_ip] timeout"

    log "Instance $_INSTANCE_ID started"
}


############# MAIN LOGIC ################
export AWS_PROFILE="dbidev"
export AWS_DEFAULT_REGION="eu-west-1"

# INPUT VARS
TG_NAME="Chariot"
ASG_NAME="Darky-ASG"
LC_PREFIX="Darky-LC-SuperApp"


# 1. Get one of the instances from TG
INSTANCE_LIST=($(get_registered_instances_from_alb_tg $TG_NAME))
INSTANCE_ID=${INSTANCE_LIST[0]}

# 2. Deploy
echo "DEPLOY STEP HERE"

# 3. Disable AS processes on AS group by InstanceId
DO_ENABLE_ASG=$(disable_autoscaling_by_instance_id $INSTANCE_ID)

# 4. Stop instance prior to making AMI
stop_instance $INSTANCE_ID

# 5. Make AMI from Instance by ID
AMI_ID="$(create_ami_by_instance_id $INSTANCE_ID)"

# 6. Start instance (required for creating new LC from instance)
start_instance $INSTANCE_ID

# 7. Create LC from Instance
OLD_LC_NAME=$(get_lc_from_asg $ASG_NAME)
NEW_LC_NAME="$LC_PREFIX-`date +'%y%m%d-%H-%M-%S'`"
wait_for_instance_state $INSTANCE_ID "running" $START_STOP_TIMEOUT_SEC
create_lc_from_instance_with_new_ami $OLD_LC_NAME $NEW_LC_NAME $INSTANCE_ID $AMI_ID

# 8. Update AS group with new LC
update_asg_with_lc $ASG_NAME $NEW_LC_NAME

# 9. Resume suspended processes on ASG
enable_asg $ASG_NAME $DO_ENABLE_ASG