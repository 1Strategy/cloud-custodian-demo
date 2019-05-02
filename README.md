# Cloud Custodian Resource Cleanup

- [How it Works](#how_it_works)
- [The Demo Policies](#demo_policies)
  - [Cost Control](#cost)
  - [Tagging Enforcement](#tagging)
  - [Security - general resources](#security_general)
  - [Security - IAM resources](#security_iam)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Concepts and Terms](#concepts_and_terms)
- [Working with Policies](#working_with_policies)
- [More About Modes](#modes)

## <a id="how_it_works"></a>How it Works

[Cloud Custodian](https://developer.capitalone.com/opensource-projects/cloud-custodian) is a rules engine for managing AWS resources at scale. You define the rules that your resources should follow, and Cloud Custodian automatically provisions event sources and AWS Lambda functions to enforce those rules. Instead of writing custom serverless workflows, you can manage resources across all of your accounts via simple YAML files.

Cloud Custodian documentation: [here](https://cloudcustodian.io/docs/quickstart/index.html#)

## <a id="demo_policies"></a>The Demo Policies

The policies are split out into four different files, to showcase the different uses of Cloud Custodian. Each Cloud Custodian policy file has a corresponding IAM policy file; this IAM policy contains the permissions required if you choose to execute the Cloud Custodian policy via a Lambda function.

### <a id="cost"></a>Cost control

- Cloud Custodian policy file: `cost-control.yml`
- IAM policy file: `cost-control-permissions.json`

Policies:

#### ec2-stop- and start-instances-offhours

Together, these policies turn on instances during business hours (8 am to 8pm), and turn them off in the evening. Perfect for dev/test environments; if implemented, this results in a ~50% decrease in instance costs.

#### ec2-change-underutilized-instance-type

This watches for large instances that are running at less than 30% CPU utilization for a given period of time, and resizes them to the next-smaller instance type.

The cost savings for this policy can be significant: a single m4.10xlarge instance, resized to a m4.4xlarge, will save $878.40 a month.

#### ec2-terminate-old-instances

This policy terminates instances that are older than 30 days. Not something you'd want to run in production, but ideal for dev accounts where resources tend to get created...and forgotten. Cleaning up just 5 abandoned m4.xlarge instances (forgotten auto-scaling group, anyone?)results in a $732/month cost reduction.

#### ebs-delete-unattached-volumes

What to do with orphaned EBS volumes you're no longer using? Delete them! This deletes any EBS volume that's not attached to an instance. Again, not something you'd want to run in prod, but a handy tool for dev accounts.

### <a id="tagging"></a>Tagging enforcement

- Cloud Custodian policy file: `tagging.yml`
- IAM policy file: `tagging-permissions.json`

Policies:

#### ec2-tag-instances-with-custodian-tag

This tags instances with `Custodian: true` as they enter the running state, to signify that the resource is being managed by Cloud Custodian. All other policies are applied to resources with this tag. If a resource is not intended to be managed by Custodian policies, the tag can be removed.

#### ec2-notify-on-no-cost-center-tag

Let's say that you want to have all instances tagged with a `CostCenter` tag. However, people are people, which means they'll forget to add tags. Every day, this will find instances that don't have these tags, and send emails to the owners of these resources. (This assumes that instances have an OwnerContact tag that contains an email address for the person who created it.)

### <a id="security_general"></a>Security remediations - general resources

- Cloud Custodian policy file: `security.yml`
- IAM policy file: `security-permissions.json`

Policies:

#### s3-revoke-global-access

Need something to take action immediately if a bucket is created with (or given) a public ACL? Even though ACLs are being deprecated in favor of bucket policies, it still happens. This policy watches for the relevant CloudTrail events, and then removes public grants if they are found.

#### security-group-revoke-global-ssh-on-creation

Creating a security group that opens up SSH to the world is a bad idea. This policy stops it. When a CloudTrail event associated with security group rule creation comes in, it detects whether it allows SSH from anywhere - and promptly removes the rule if it does.

#### security-group-revoke-all-tcp-global-on-creation

Like the "global SSH is a bad thing" policy (above), this one watches for the creation of security group rules allowing access to the world on all port ranges...and then deletes those rules.

### <a id="security_iam"></a>Security remediations - IAM

- Cloud Custodian policy file: `iam.yml`
- IAM policy file: `iam-permissions.json`

These policies are in a separate file because all IAM-related policies must be run in `us-east-1` (the home of IAM). Policies:

#### iam-policy-notify-on-admin-policy-attachment

Want to know when some attaches a policy with admin (* on *) privileges to a user, group, or role? This is your policy.

#### iam-policy-notify-on-admin-policy-creation

If you want to take this admin-permissions thing one step further, this policy will alert you when a policy is created with * on * permissions.

## <a id="prerequisites"></a>Prerequisites

Install python, pip, and [Pipenv](https://github.com/pypa/pipenv)

## <a id="installation"></a>Installation

To install Cloud Custodian, run:

``` bash
$ git clone this repo
$ pipenv install
$ pipenv shell
$ custodian -h
```

## <a id="concepts_and_terms"></a>Concepts and Terms

- **Policy** Policies first specify a resource type, then filter those resources, and finally apply actions to those selected resources. Policies are written in YML format.
- **Resource** Within your policy, you write filters and actions to apply to different resource types (e.g. EC2, S3, RDS, etc.). Resources are retrieved via the AWS API; each resource type has different filters and actions that can be applied to it.
- **Filter** [Filters](https://capitalone.github.io/cloud-custodian/docs/policy/index.html) are used to target the specific subset of resources that you're interested in. Some examples: EC2 instances more than 90 days old; S3 buckets that violate tagging conventions.
- **Action** Once you've filtered a given list of resources to your liking, you apply [actions](https://capitalone.github.io/cloud-custodian/docs/policy/index.html) to those resources. Actions are verbs: e.g. stop, start, encrypt.
- **Mode** `Mode` specifies how you would like the policy to be deployed. If no mode is given, the policy will be executed once, from the CLI, and no lambda will be created. (This is often called `pull mode` in the documentation.) If your policy contains a `mode`, then a lambda will be created, plus any other resources required to trigger that lambda (e.g. CloudWatch event, Config rule, etc.). Check out the [More About Modes](#modes) section for more info.

## <a id="working_with_policies"></a>Working with Policies

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

Before running the policy, you'll need to give the resulting Lambda function the permissions required. Use the IAM policy provided for each Cloud Custodian policy file as a starting place: create the policy, attach it to a new role, and update the Cloud Custodian policy with the ARN of that role.

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

### Set up the mailer

Some of the policies send notifications via SNS, email, or Slack. To send notifications, you'll need to implement the Mailer tool in your account. Instructions on how to do this are in [usingTheMailer.md](usingTheMailer.md). An IAM policy with permissions required by the mailer is in [mailer-permissions.json](mailer-permissions.json).

## <a id="modes"></a>More About Modes

Modes can be confusing. Here are the different mode types, what they do, and what their `yml` block should look like:

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
