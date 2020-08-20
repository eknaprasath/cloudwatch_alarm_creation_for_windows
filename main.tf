resource "aws_ssm_parameter" "CW-Linux-Config" {
  name  = "CW-Linux-Config"
  type  = "String"
  value = <<EOF
{
	"agent": {
		"metrics_collection_interval": 60,
		"run_as_user": "cwagent"
	},
	"metrics": {
		"append_dimensions": {
			"AutoScalingGroupName": "$${aws:AutoScalingGroupName}",
			"InstanceId": "$${aws:InstanceId}"
		},
		"metrics_collected": {
			"disk": {
				"measurement": [
					"used_percent"
				],
				"metrics_collection_interval": 60,
				"resources": [
					"*"
				]
			},
			"mem": {
				"measurement": [
					"mem_used_percent"
				],
				"metrics_collection_interval": 60
			},
			"statsd": {
				"metrics_aggregation_interval": 60,
				"metrics_collection_interval": 10,
				"service_address": ":8125"
			}
		}
	}
}
  EOF
}


resource "aws_ssm_document" "cloudwatch_alarm_creation" {
  name          = "cloudwatch_alarm_creation"
  document_type = "Automation"
  document_format = "YAML"

  content = <<DOC
description: Install and Configure CloudWatch on Instance
schemaVersion: '0.3'
parameters:
  InstanceIds:
    type: String
    description: (Required) Cloudwtach agent to be installed.
  action:
    description: (Required) Specify whether or not to install or uninstall the package.
    type: String
    allowedValues:
      - Install
      - Uninstall
  installationType:
    description: >-
      (Optional) Specify the type of installation. Uninstall and reinstall: The
      application is taken offline until the reinstallation process completes.
      In-place update: The application is available while new or updated files
      are added to the installation.
    type: String
    allowedValues:
      - Uninstall and reinstall
      - In-place update
    default: Uninstall and reinstall
  name:
    description: (Required) The package to install/uninstall.
    type: String
    allowedPattern: >-
      ^arn:[a-z0-9][-.a-z0-9]{0,62}:[a-z0-9][-.a-z0-9]{0,62}:([a-z0-9][-.a-z0-9]{0,62})?:([a-z0-9][-.a-z0-9]{0,62})?:(package|document)\/[a-zA-Z0-9/:.\-_]{1,128}$|^[a-zA-Z0-9/:.\-_]{1,128}$
    default: AmazonCloudWatchAgent
  version:
    description: >-
      (Optional) The version of the package to install or uninstall. If you
      don’t specify a version, the system installs the latest published version
      by default. The system will only attempt to uninstall the version that is
      currently installed. If no version of the package is installed, the system
      returns an error.
    type: String
    default: ''
  cwaction:
    description: The action CloudWatch Agent should take.
    type: String
    default: configure
    allowedValues:
      - configure
      - configure (append)
      - start
      - status
      - stop
  mode:
    description: >-
      Controls platform-specific default behavior such as whether to include EC2
      Metadata in metrics.
    type: String
    default: ec2
    allowedValues:
      - ec2
      - onPremise
      - auto
  optionalConfigurationSource:
    description: >-
      Only for 'configure' action. Store of the configuration. For CloudWatch
      Agent's defaults, use 'default'
    type: String
    allowedValues:
      - default
      - ssm
    default: ssm
  optionalConfigurationLocation:
    description: >-
      Only for 'configure' actions. Required if loading CloudWatch Agent config
      from other locations except 'default'. The value is like ssm parameter
      store name for ssm config source.
    type: String
    default: CW-Linux-Config
    allowedPattern: '[^"]*'
  optionalRestart:
    description: >-
      Only for 'configure' actions. If 'yes', restarts the agent to use the new
      configuration. Otherwise the new config will only apply on the next agent
      restart.
    type: String
    default: 'yes'
    allowedValues:
      - 'yes'
      - 'no'
mainSteps:
  - name: InstallCWAgent
    maxAttempts: 3
    inputs:
      Parameters:
        action: '{{action}}'
        installationType: '{{installationType}}'
        name: '{{name}}'
        version: '{{version}}'
      InstanceIds:
        - '{{InstanceIds}}'
      DocumentName: AWS-ConfigureAWSPackage
      CloudWatchOutputConfig:
        CloudWatchLogGroupName: CloudWatchGroupForSSMAutomationService
        CloudWatchOutputEnabled: true
    action: 'aws:runCommand'
    timeoutSeconds: 1800
    onFailure: Abort
  - name: ConfigureCWAgent
    maxAttempts: 3
    inputs:
      Parameters:
        action: '{{cwaction}}'
        mode: '{{mode}}'
        optionalConfigurationSource: '{{optionalConfigurationSource}}'
        optionalConfigurationLocation: '{{optionalConfigurationLocation}}'
        optionalRestart: '{{optionalRestart}}'
      InstanceIds:
        - '{{InstanceIds}}'
      DocumentName: AmazonCloudWatch-ManageAgent
      CloudWatchOutputConfig:
        CloudWatchLogGroupName: CloudWatchGroupForSSMAutomationService
        CloudWatchOutputEnabled: true
    action: 'aws:runCommand'
    timeoutSeconds: 1800
    onFailure: Abort
  - name: listblockdevice
    action: 'aws:runCommand'
    onFailure: Abort
    inputs:
      DocumentName: AWS-RunShellScript
      InstanceIds:
        - '{{ InstanceIds }}'
      Parameters:
        commands:
          - '#!/bin/sh '
          - 'df -TPh | grep -v "tmpfs" | awk ''BEGIN {printf"{\"discarray\":["}{if($1=="Filesystem")next;if(a)printf",";printf"{\"Filesystem\":\""$1"\",\"fstype\":\""$2"\",\"size\":\""$3"\",\"used\":\""$4"\",\"available\":\""$5"\",\"usedpercent\":\""$6"\",\"mount\":\""$7"\"}";a++;}END{print"]}";}'''
    outputs:
      - Name: blockdevice
        Selector: $.Output
        Type: String
  - name: createalarm
    action: 'aws:invokeLambdaFunction'
    timeoutSeconds: 1200
    maxAttempts: 1
    onFailure: Abort
    inputs:
      FunctionName: CW-Alarm-Creation
      Payload: '{"instanceid":"{{InstanceIds}}","Blockdevice": {{listblockdevice.blockdevice}}}'
DOC
}
