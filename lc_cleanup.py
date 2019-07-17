#!/usr/bin/env python3

import boto3
from pprint import pprint
from dateutil.tz import tzutc
import datetime
import logging
from os import environ

logger = logging.getLogger()
# logger.setLevel(logging.INFO)
logging.basicConfig(level=logging.INFO, format='%(message)s')


class LaunchConfigsCleaner():
    def __init__(self, profile, region, dryrun):
        self.profile = profile
        self.region = region
        self.dryrun = dryrun

        boto_session = boto3.Session(profile_name=profile, region_name=region)
        self.as_client = boto_session.client('autoscaling')

        self.lc_list = self.get_lc_list()
        self.asg_list = self.get_asg_list()

    def get_lc_list(self):
        self.lc_list = []
        response = self.as_client.describe_launch_configurations(
            LaunchConfigurationNames=[]
        )
        self.lc_list = response['LaunchConfigurations']
        while 'NextToken' in response:
            response = self.as_client.describe_launch_configurations(
                LaunchConfigurationNames=[],
                NextToken=response['NextToken']
            )
            self.lc_list += response['LaunchConfigurations']
        return self.lc_list

    def get_asg_list(self):
        self.asg_list = []
        response = self.as_client.describe_auto_scaling_groups(
            AutoScalingGroupNames=[]
        )
        self.asg_list = response['AutoScalingGroups']
        while 'NextToken' in response:
            response = self.as_client.describe_auto_scaling_groups(
                AutoScalingGroupNames=[],
                NextToken=response['NextToken']
            )
            self.asg_list += response['AutoScalingGroups']

        return self.asg_list

    def remove_launch_configuration(self, lc):
        ''' Check if not attached to any ASG and remove if not '''
        lc_active = self.check_lc_active(lc)
        lc_create_time = lc['CreatedTime'].isoformat()
        if lc_active:
            logger.warning('%5s ACTIVE  %-75s %s' % ('', lc['LaunchConfigurationName'], lc_create_time))
            return False
        else:
            if not self.dryrun:
                try:
                    self.as_client.delete_launch_configuration(
                        LaunchConfigurationName=lc['LaunchConfigurationName']
                    )
                    pass
                except Exception:
                    logger.error('Some error during delete of %s. Continuing' % (lc['LaunchConfigurationName']))
            DRYRUN_MSG = "(DRYRUN)" if self.dryrun else ''
            logger.warning('%5s REMOVE %s %-75s %s' % ('', DRYRUN_MSG, lc['LaunchConfigurationName'], lc_create_time))

            return lc

    def check_lc_active(self, lc):
        for asg in self.asg_list:
            if lc['LaunchConfigurationName'] in asg['LaunchConfigurationName']:
                return True
        else:
            return False

    def remove_launch_configurations_older_than(self, outdated_date):
        ''' date is like '01-01-2015' '''
        removed_lc_list = []
        outdated_dt = datetime.datetime.strptime(outdated_date, '%d-%m-%Y').replace(tzinfo=tzutc())
        for lc in self.lc_list:
            lc_create_time = lc['CreatedTime'].isoformat()
            if lc['CreatedTime'] < outdated_dt:
                removed_lc = self.remove_launch_configuration(lc)
                if removed_lc:
                    removed_lc_list.append(removed_lc)
            else:
                logger.warning('%5s INTACT  %-75s %s' % ('', lc['LaunchConfigurationName'], lc_create_time))

        return removed_lc_list

    def find_launch_configs_with_basename(self, basename):
        lc_of_same_asg = []
        for lc in self.lc_list:
            if basename in lc['LaunchConfigurationName']:
                lc_of_same_asg.append(lc)
        return lc_of_same_asg

    def get_active_launch_configs(self):
        active_lc_list = []
        for lc in self.lc_list:
            if self.check_lc_active(lc):
                active_lc_list.append(lc)
        return active_lc_list

    def remove_oldest_lc_of_group(self, basename, lc_list, num):
        ''' Remove oldest LaunchConfigurations of <lc_list> provided,
            but keep latest <num> LCs
            Return list of removed LCs
        '''
        removed_lc_list = []
        logger.warning('Basename - %-40s' % (basename))
        if len(lc_list) <= num:
            logger.warning('%5s NUMBER_OF_LATEST_LC_TO_KEEP is less or equal to %s. Not removing.' % ('', num))
            for lc in lc_list:
                logger.warning("%5s Retaining %s" % ('', lc['LaunchConfigurationName']))
            return False
        else:
            sorted_lc_list = sorted(lc_list, key=lambda lc: lc['CreatedTime'], reverse=True)
            lc_retain_list = sorted_lc_list[:num]

            for lc in lc_retain_list:
                logger.warning("%5s Keep %s latest %-68s %s" % ('', num, lc['LaunchConfigurationName'], lc['CreatedTime']))

            lc_removal_list = sorted_lc_list[num:]
            for lc in lc_removal_list:
                removed_lc = self.remove_launch_configuration(lc)
                if removed_lc:
                    removed_lc_list.append(removed_lc)
        return removed_lc_list


def main(event, context):
    env_region = environ.get('REGION', 'us-east-1')
    env_profile = environ.get('PROFILE', None)
    env_dryrun = False if environ.get('DRYRUN', 'false').lower() in ['false', 'no'] else True

    number_of_lc_to_keep = environ.get('NUMBER_OF_LATEST_LC_TO_KEEP', '')
    obsolete_date = environ.get('OBSOLETE_DATE', '')
    delimiter = environ.get('DELIMITER', '-AppLaunchConfiguration')

    # OBSOLETE_DATE validation
    try:
        datetime.datetime.strptime(obsolete_date, '%d-%m-%Y')
    except Exception:
        logger.error('Incorrect date format in OBSOLETE_DATE. Should be DD-MM-YYYY. Skipping date-based LC removal.')
        obsolete_date = False

    # NUMBER_OF_LATEST_LC_TO_KEEP validation
    if not number_of_lc_to_keep.isdigit():
        logger.error('NUMBER_OF_LATEST_LC_TO_KEEP should be a number. Skipping removal method \'keep N latest lc per asg\'.')
        number_of_lc_to_keep = False

    cleaner = LaunchConfigsCleaner(profile=env_profile, region=env_region, dryrun=env_dryrun)
    print (len(cleaner.lc_list))
    if obsolete_date:
        #outdated_date = '01-01-2017'
        cleaner.remove_launch_configurations_older_than(obsolete_date)

    if number_of_lc_to_keep and delimiter:
        logging.info('Start LC removal based on keeping N latest LC for every ASG')
        active_lc_list = cleaner.get_active_launch_configs()
        for lc in active_lc_list:
            if delimiter not in lc['LaunchConfigurationName']:
                logger.warning('Skip LC - %s. Not covered with any pattern.' % (lc['LaunchConfigurationName']))
                continue
            lc_basename = lc['LaunchConfigurationName'].split(delimiter)[0]

            lc_group = cleaner.find_launch_configs_with_basename(''.join([lc_basename, delimiter]))

            cleaner.remove_oldest_lc_of_group(lc_basename, lc_group, num=int(number_of_lc_to_keep))


if __name__ == "__main__":
    main(None, None)

'''
Removal #1. Remove old LCs.
    (Requires OBSOLETE_DATE env)
    Get list of all LCs
    Remove LCs if older than some date set by OBSOLETE_DATE env (if set)

Removal #2. Keep N latest LCs og f ASG
    (Requires NUMBER_OF_LATEST_LC_TO_KEEP and optionally DELIMITER env)
    Get all active LCs attached to ASG
    Extract 'basename' of each active LC that has DELIMITER in its name
      Get list of LC containing basename
      If list contains more than NUMBER_OF_LATEST_LC_TO_KEEP entries, then remove older LCs keeping NUMBER_OF_LATEST_LC_TO_KEEP number


LC
{u'BlockDeviceMappings': [],
 u'ClassicLinkVPCSecurityGroups': [],
 u'CreatedTime': datetime.datetime(2014, 1, 7, 18, 43, 50, 686000, tzinfo=tzutc()),
 u'EbsOptimized': False,
 u'IamInstanceProfile': 'as-cert-app',
 u'ImageId': 'ami-970135fe',
 u'InstanceMonitoring': {u'Enabled': True},
 u'InstanceType': 'm1.medium',
 u'KernelId': '',
 u'KeyName': 'HMHVPC01-ASCERTAPP',
 u'LaunchConfigurationARN': 'arn:aws:autoscaling:us-east-1:205685244378:launchConfiguration:028be624-0dea-4136-bf12-fbddd4f5d6eb:launchConfigurationName/ASCERTv4-ASLaunchConfig1-1KFGRNPSNMH5C',
 u'LaunchConfigurationName': 'ASCERTv4-ASLaunchConfig1-1KFGRNPSNMH5C',
 u'RamdiskId': '',
 u'SecurityGroups': ['sg-67c43802'],
 u'UserData': ''}
 
ASG
{'AutoScalingGroupARN': 'arn:aws:autoscaling:us-east-1:205685244378:autoScalingGroup:0d158249-abfe-4408-be27-d12d782885ef:autoScalingGroupName/HMHDEVVPC01-HMOF-INTC-APP-AppAutoScalingGroupCAES-1MWUSF24TLY7U',
 'AutoScalingGroupName': 'HMHDEVVPC01-HMOF-INTC-APP-AppAutoScalingGroupCAES-1MWUSF24TLY7U',
 'AvailabilityZones': ['us-east-1a'],
 'CreatedTime': datetime.datetime(2016, 6, 3, 9, 25, 40, 202000, tzinfo=tzutc()),
 'DefaultCooldown': 600,
 'DesiredCapacity': 1,
 'EnabledMetrics': [],
 'HealthCheckGracePeriod': 300,
 'HealthCheckType': 'EC2',
 'Instances': [{'AvailabilityZone': 'us-east-1a',
                'HealthStatus': 'Healthy',
                'InstanceId': 'i-0d053795da71f6f88',
                'LifecycleState': 'InService',
                'ProtectedFromScaleIn': False}],
 'LaunchConfigurationName': 'HMHDEVVPC01-HMOF-INTC-CAES-AppLaunchConfiguration-180413-13-31-20',
 'LoadBalancerNames': ['HMHDEVVPC01-HMOF-INTC-CAES'],
 'MaxSize': 1,
 'MinSize': 1,
 'NewInstancesProtectedFromScaleIn': False,
 'ServiceLinkedRoleARN': 'arn:aws:iam::205685244378:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling',
 'SuspendedProcesses': [],
 'Tags': [],
 'TargetGroupARNs': [],
 'TerminationPolicies': ['Default'],
 'VPCZoneIdentifier': 'subnet-9749c7f6'}
 '''