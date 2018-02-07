# Cloud Custodian Resource Cleanup

## How It Works

[Cloud Custodian](https://developer.capitalone.com/opensource-projects/cloud-custodian) is a rules engine for managing AWS resources at scale. You define the rules that your resources should follow, and Cloud Custodian automatically provisions event sources and lambda functions to enforce those rules. Instead of writing custom serverless workflows, you can manage resources across all of your accounts via simple YML files.

The policy specified in the accompanying `policy.yml` file will execute once a day, and will delete all instances tagged `Custodian` that are older than 30 days.

Below is an overview of Cloud Custodian; more information is in the [docs](http://capitalone.github.io/cloud-custodian/docs/index.html).

## Prerequisites

Install python, pip, and [Pipenv](https://github.com/pypa/pipenv)

## Installation

To install Cloud Custodian, run:

``` bash
$ git clone this repo
$ pipenv install
$ pipenv shell
$ custodian -h
```

## Concepts and Terms

- **Policy** Policies first specify a resource type, then filter those resources, and finally apply actions to those selected resources. Policies are written in YML format.
- **Resource** Within your policy, you write filters and actions to apply to different resource types (e.g. EC2, S3, RDS, etc.). Resources are retrieved via the AWS API; each resource type has different filters and actions that can be applied to it.
- **Filter** [Filters](https://capitalone.github.io/cloud-custodian/docs/policy/index.html) are used to target the specific subset of resources that you're interested in. Some examples: EC2 instances more than 90 days old; S3 buckets that violate tagging conventions.
- **Action** Once you've filtered a given list of resources to your liking, you apply [actions](https://capitalone.github.io/cloud-custodian/docs/policy/index.html) to those resources. Actions are verbs: e.g. stop, start, encrypt.
- **Mode** `Mode` specifies how you would like the policy to be deployed. If no mode is given, the policy will be executed once, from the CLI, and no lambda will be created. (This is often called `pull mode` in the documentation.) If your policy contains a `mode`, then a lambda will be created, plus any other resources required to trigger that lambda (e.g. CloudWatch event, Config rule, etc.). Check out the [More About Modes](#modes) section for more info.

## Working with the `policy.yml` file

The EC2 instance policies are laid out in the `policy.yml` file.

### Updating policies

The filters and actions available to you vary depending on the targeted resource (e.g. EC2, S3, etc.). Cloud Custodian has good CLI documentation to help you find the right filter or action for your needs. To get started, run

``` bash
custodian schema -h
```

to see all the different resources that Cloud Custodian supports. Then, to see the resource-specific filters/actions, run

``` bash
custodian schema [resourceName]
```

for example:

``` bash
custodian schema EC2
```

will list the filters and actions available for EC2. For details on a specific action or filter, the format is:

``` bash
custodian schema [resourceName].[actions or filters].[action or filter name]
```

for example:

``` bash
custodian schema EC2.filters.instance-age
```

### Configure the IAM role

Before running the policy, you'll need to give the resulting lambda function the permissions required. The following policy will work; you will likely want to restrict it further to suit your needs. Create a role that uses this policy, and then update the ARN of the role in the `policy.yml` file.

``` JSON
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams",
                "logs:GetLogEvents",
                "logs:FilterLogEvents",
                "logs:CreateLogGroup",
                "logs:PutLogEvents"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "cloudwatch:PutMetricData"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:TerminateInstances"
            ],
            "Resource": "arn:aws:ec2:us-west-2:*:instance/*"
        }
    ]
}
```

### Validate the policies

Once you've updated your policies, you'll want to run the Cloud Custodian validator to check the file for errors:

``` bash
custodian validate policy.yml
```

### Dry-run the policies

It's a good idea to "dry-run" policies before actually deploying them. A "dry-run" will query the AWS API for resources that match the given filters, then save those resources in a `resources.json` file for each policy.

``` bash
custodian run --dryrun -s output policy.yml
```

The `--dryrun` option ensures that no actions are taken, while the `-s` option specifies the path for output files (in this case, the output directory). Each policy will have its own subdirectory containing the output files. In this example, the resources selected by a policy named `ec2-terminate-old-instances` would be contained in `output/ec2-terminate-old-instances/resources.json`.

### Deploy the policies

Once you're satisfied with the results of your filters, deploy the policies with:

``` bash
custodian run -s . policy.yml
```

Cloud Custodian will take care of creating the needed lambda functions, CloudWatch events, etc. Sit back and watch it work!

## <a name="modes">More About Modes</a>

Cloud Custodian generally has very good documentation; the `mode` options, however, are less well documented. Here are the different mode types, what they do, and what their `yml` block should look like:

### asg-instance-state

`asg-instance-state` triggers the lambda in response to [Auto Scaling group state events](https://docs.aws.amazon.com/autoscaling/ec2/userguide/cloud-watch-events.html) (e.g. Auto Scaling launched an instance). The four events supported are:

| yml option | AWS ASG event `detail-type` |
| ---------- | --------------------------- |
|`launch-success` | "EC2 Instance Launch Successful" |
|`launch-failure` | "EC2 Instance Launch Unsuccessful" |
|`terminate-success` | "EC2 Instance Terminate Successful" |
|`terminate-failure` | "EC2 Instance Terminate Unsuccessful" |

Example:

``` yml
mode:
    role: #ARN of the IAM role you want the lambda to use
    type: asg-instance-state
    events:
        - launch-success
```

### cloudtrail

`cloudtrail` triggers the lambda in response to [CloudTrail events](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-event-reference.html). The `cloudtrail` type comes in a couple different flavors: events for which there are shortcuts, and all other events.

#### Shortcuts

For very common API calls, Cloud Custodian has defined some [shortcuts](https://github.com/capitalone/cloud-custodian/blob/master/c7n/cwe.py#L28-L84) to target commonly-used CloudTrail events.

As of this writing, the available shortcuts are:

    - ConsoleLogin
    - CreateAutoScalingGroup
    - UpdateAutoScalingGroup
    - CreateBucket
    - CreateCluster
    - CreateLoadBalancer
    - CreateLoadBalancerPolicy
    - CreateDBInstance
    - CreateVolume
    - SetLoadBalancerPoliciesOfListener
    - CreateElasticsearchDomain
    - CreateTable
    - RunInstances

For those shortcuts, you simply need to specify:

``` yml
mode:
    role: #ARN of the IAM role you want the lambda to use
    type: cloudtrail
    events:
        - RunInstances
```

#### Other CloudTrail Events

You can also trigger your lambda via any other CloudTrail event; you'll just have to add two more pieces of information. First, you need the source API call - e.g. `ec2.amazonaws.com`. Secondly, you need a JMESPath query to extract the resource IDs from the event. For example, if `RunInstances` wasn't already a shortcut, you would specify it like so:

``` yml
mode:
    role: #ARN of the IAM role you want the lambda to use
    type: cloudtrail
    events:
        - source: ec2.amazonaws.com
          event: RunInstances
          ids: "responseElements.instancesSet.items[].instanceId"

```

### config-rule

`config-rule` creates a [custom Config Rule](https://docs.aws.amazon.com/config/latest/developerguide/evaluate-config_develop-rules.html) to trigger the lambda. Config rules themselves can only be triggered by configuration changes; triggering rules periodically is not supported. Use the `periodic` mode type instead.

Example:

``` yml
mode:
    role: #ARN of the IAM role you want the lambda to use
    type: config-rule
```

### ec2-instance-state

`ec2-instance-state` triggers the lambda in response to EC2 instance state events (e.g. an instance being created and entering `pending` state).

Available states:

    - pending
    - running
    - stopping
    - stopped
    - shutting-down
    - terminated
    - rebooting

Example:

``` yml
mode:
    role: #ARN of the IAM role you want the lambda to use
    type: ec2-instance-state
    events:
        - pending
```

### guard-duty

With `guard-duty`, your lambda will be triggered by [GuardDuty findings](https://docs.aws.amazon.com/guardduty/latest/ug/guardduty_findings.html). The associated filters would then look at the guard duty event detail - e.g. `severity` or `type`.

``` yml
mode:
    role: #ARN of the IAM role you want the lambda to use
    type: periodic
filters:
    - type: event
      key: detail.severity
      op: gte
      value: 4.5
```

### periodic

`periodic` creates a CloudWatch event to trigger the lambda on a given schedule. The `schedule` is specified using [scheduler syntax](https://docs.aws.amazon.com/AmazonCloudWatch/latest/events/ScheduledEvents.html).

Example:

``` yml
mode:
    role: #ARN of the IAM role you want the lambda to use
    type: periodic
    schedule: "rate(1 day)"
```
