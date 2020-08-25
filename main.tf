resource "aws_ssm_parameter" "CW-Windows-Config" {
  name  = "CW-Windows-Config"
  type  = "String"
  value = <<EOF
{
	"metrics": {
		"append_dimensions": {
			"AutoScalingGroupName": "$${aws:AutoScalingGroupName}",
			"ImageId": "$${aws:ImageId}",
			"InstanceId": "$${aws:InstanceId}",
			"InstanceType": "$${aws:InstanceType}"
		},
		"metrics_collected": {
			"LogicalDisk": {
				"measurement": [
					"% Free Space"
				],
				"metrics_collection_interval": 60,
				"resources": [
					"*"
				]
			},
			"Memory": {
				"measurement": [
					"% Committed Bytes In Use"
				],
				"metrics_collection_interval": 60
			}
		}
	}
}
  EOF
}


resource "aws_ssm_document" "cloudwatch_alarm_creation_windows" {
  name          = "cloudwatch_alarm_creation_windows"
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
    default: CW-Windows-Config
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
      DocumentName: AWS-RunPowerShellScript
      InstanceIds:
        - '{{ InstanceIds }}'
      Parameters:
        commands:
          - 'Get-WmiObject -Class Win32_logicaldisk| Select-Object -Property DeviceID | ConvertTo-Json'
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
      FunctionName: CW-Alarm-Creation-windows
      Payload: '{"instanceid":"{{InstanceIds}}","Blockdevice": {{listblockdevice.blockdevice}}}'
DOC
}
