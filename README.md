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
(custodian) $ custodian -h
```

## Concepts and Terms

- **Policy** Policies first specify a resource type, then filter those resources, and finally apply actions to those selected resources. Policies are written in YML format.
- **Resource** Within your policy, you write filters and actions to apply to different resource types (e.g. EC2, S3, RDS, etc.). Resources are retrieved via the AWS API; each resource type has different filters and actions that can be applied to it.
- **Filter** Filters are used to target the specific subset of resources that we're interested in. Some examples: EC2 instances more than 90 days old; S3 buckets that violate tagging conventions.
- **Action** Once you've filtered a given list of resources to your liking, you apply actions to those resources. Actions are verbs: e.g. stop, start, encrypt.
- **Mode** The mode specifies how the resource rule will execute. When deploying long-running rules (vs. a one-time enforcement), these modes are used:
  - `config-rule`: Executes as an AWS Config rule
  - `cloud-trail`: Executes in response to CloudTrail events
  - `periodic`: Executes on a cron schedule

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
