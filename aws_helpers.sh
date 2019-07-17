https://opensourceconnections.com/blog/2015/07/27/advanced-aws-cli-jmespath-query/
https://www.onica.com/blog/using-aws-cli-to-find-untagged-instances/

AWS="aws"

# Get inbound rules of SG
SG_ID="sg-24831441"
aws --profile hmhdublindev ec2 describe-security-groups --group-ids sg-24831441 --query 'SecurityGroups[].IpPermissions[].[ToPort,IpProtocol,IpRanges[].CidrIp,UserIdGroupPairs[].GroupId]' --output text


### Get all SGs of instance and all its rules
INSTANCE_ID="i-07c1229b053c4c12a"
SG_LIST=$(aws --profile hmhdublindev ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[].Instances[].SecurityGroups[].GroupId' --output text)

for sg_id in `echo $SG_LIST`; do
    echo "Security Group - $sg_id. Rules."
    echo "===================================="
    aws --profile hmhdublindev ec2 describe-security-groups --group-ids $sg_id --query 'SecurityGroups[].IpPermissions[].[ToPort,IpProtocol,IpRanges[].CidrIp,UserIdGroupPairs[].GroupId]' --output text
done



### Find and remove unused LCs
OLD_LC_LIST=$($AWS autoscaling describe-launch-configurations \
    --query 'LaunchConfigurations[?CreatedTime <= `2018-01-01`].[LaunchConfigurationName]' --output text)

for lc in `echo $OLD_LC_LIST`; do
    LC_ATTACHED=$($AWS autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[?LaunchConfigurationName == '$lc'].AutoScalingGroupName" --output text)
    if [[ -z "$LC_ATTACHED" ]]; then
        echo "LC - $lc       - not attached to any ASG. Removing."
        # $AWS autoscaling delete-launch-configuration --launch-configuration-name $lc
    else
        echo "LC - $lc       - can't be removed. attached to $LC_ATTACHED"
    fi
done


### Get images list with criterias
aws ec2 describe-images --owner 205685244378 --query 'Images[?Name!=`null`]|[? Tags[? Value==`2017-11-01` && Key==`expire_orig`]]|[?!not_null(Tags[?Key == `CI-Tool`].Value)]|[?CreationDate <= `2017-11-01`].[CreationDate,ImageId,Name]' --output text



### Find if SG is in use 
aws --profile hmhdublindev ec2 describe-instances --query  "Reservations[].Instances[?SecurityGroups[?GroupId == 'sg-86dc1fe2']].InstanceId" --output text


# Find User of AccessKey 
ACCESS_KEY=AKIAIOGYOQUPI7GXPYEA
USERS=$(aws --profile hmhdublindev iam list-users --query Users[].UserName --output text)
for username in $USERS; do
    aws --profile hmhdublindev iam list-access-keys --user-name "$username" --query "AccessKeyMetadata[?AccessKeyId == '$ACCESS_KEY'].UserName" --output text
done


# Get decoded Userdata of LCs
aws --profile hmhdublindev autoscaling describe-launch-configurations --query "LaunchConfigurations[?UserData != ''].[LaunchConfigurationName,UserData]" --output text > lc_with_userdata
while read u; do
  echo $u | egrep -o "^.*\s"
  echo $u | sed -r "s/^.*\s(.*)$/\1/" | base64 -d - | grep cfn-init
done < lc_with_userdata


# Check if keys assigned to any user
ACCESS_KEY="target_access_key"
USERS=$(aws --profile hmhdublindev iam list-users --query Users[].UserName --output text)
for key in $KEYS; do
    for username in $USERS; do
        aws --profile hmhdublindev iam list-access-keys --user-name "$username" --query "AccessKeyMetadata[?AccessKeyId == '$ACCESS_KEY'].[UserName,AccessKeyId]" --output text
    done
done

# Find Openvpn 2.5.2 AMIs mapping
for region in $(aws ec2 describe-regions --query "Regions[].RegionName" --output text); do
    AMI=$(aws ec2 describe-images 
            --owners 679593333241
            --filters Name=name,Values='OpenVPN Access Server 2.5.2*'
            --query "reverse(sort_by(Images, &CreationDate))[0].ImageId"
            --output text
            --region $region)
    echo "${region}: $(aws ec2 describe-images --owners 679593333241 --filters Name=name,Values='OpenVPN Access Server 2.5.2*' --query "reverse(sort_by(Images, &CreationDate))[0].ImageId" --output text --region $region)"; done

    echo "AWSRegionToAMI:"

# ECS Optimized instances mapping
for region in $(aws ec2 describe-regions --query 'Regions[].RegionName' --output text)
do
  echo "  ${region}:"
  echo -n "    AMI: "

  aws ec2 describe-images \
    --owners amazon \
    --query 'reverse(sort_by(Images[?Name != `null`] | [?contains(Name, `amazon-ecs-optimized`) == `true`], &CreationDate))[:1].ImageId' \
    --output text \
    --region $region
  #aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 \
                       --region $region --output text --query Parameters[0].Value

done

###
for region in $(aws ec2 describe-regions --query 'Regions[].RegionName' --output text)
do
  echo "  ${region}:"
  echo -n "    AMI: "

aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 \
                       --region $region --output text --query Parameters[0].Value
done
