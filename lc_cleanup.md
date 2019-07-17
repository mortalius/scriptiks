### Launch Configurations Cleanup Script

Script behaviour is controlled by environment variables.

Common variables user

`PROFILE` - AWS profile to use. Leave blank for default or lambda use

`REGION` - 'us-east-1' by default

`DRYRUN` - True by default. To disable use 'no' or 'false'

Uses 2 removal methods

##### 1. Remove LaunchConfigurations older than some date

All LaunchConfigurations with CreatedTime attribute older than OBSOLETE_DATE will be removed

Activated by specifying following environment variables

`OBSOLETE_DATE` - date in format like **'01-01-2015'**

##### 2. Keep N latest LaunchConfigurations for every ASG

Scans for all LCs currently in use by ASG. Then makes a lists of common LCs using active LC as a starting point.

Keeps N most recent LaunchConfigurations based on CreatedTime attribure and removes the rest with prior check on activeness of LC.

Activated by specifying following environment variables

`NUMBER_OF_LATEST_LC_TO_KEEP` - as its name states

`DELIMITER` - (Optional) delimiter used to identify name of LaunchConfiguration that is common to a group of 
LaunchConfigurations for an ASG. Defaults to '-AppLaunchConfiguration'

#### Manual launch examples

Run removal for hmhdublindev account with both methods

`PROFILE=hmhdublindev NUMBER_OF_LATEST_LC_TO_KEEP=2 OBSOLETE_DATE=01-01-2017 python3 lc_cleanup.py`

Run method 2 removal with custom DELIMITER. Use default profile. 

`NUMBER_OF_LATEST_LC_TO_KEEP=2 DELIMITER='-LC' python3 lc_cleanup.py`
