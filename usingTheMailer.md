# Setting up the Cloud Custodian Mailer

These instructions are heavily based on those in the [documentation](https://github.com/capitalone/cloud-custodian/tree/master/tools/c7n_mailer).

Jump to...

- [How the mailer works](#how_it_works)
- [Setting up the mailer](#setup)

## <a id="how_it_works"></a>How the mailer works

Cloud Custodian has a number of add-on "tools" that accomplish different jobs: sending out notifications via email, exporting logs, scanning individual S3 objects, and Azure/GCP support. These tools are used in conjunction with the basic Cloud Custodian setup, and require separate installation, configuration, and deployment.

The mailer tool is one element in the overall workflow of sending notifications via Cloud Custodian. The overall flow is as follows; each step is described in more detail below.

1. Notifiaction actions
2. SQS queue
3. Mailer Lambda function
4. SES

### Notification actions

Cloud Custodian policies filter resources and then stipluate actions to be taken on those resources. Oftentimes, actions are remediation-based: tagging a resource, turning an instance on or off, or removing ACLs that allow public access from an S3 bucket.

An action can also send notifications. The `notify`-type action specifies the notification content, destination, and delivery mechanism. An explanation of how to write `notify` actions is in the "Setting up the mailer" section, below.

### SQS Queue

When a `notify` action is triggered, a message is sent to an SQS queue. The mailer Lambda will check this SQS queue for messages and process them.

### Mailer Lambda function

The Cloud Custodian [mailer](https://github.com/capitalone/cloud-custodian/tree/master/tools/c7n_mailer) tool deploys a Lambda function that runs every five minutes. When it runs, it pulls the messages out of the SQS queue, processes them, and sends them off to SES.

The mailer function is configured via a `mailer.yml` file.

### Delivery service

SES, Slack, etc.

## <a id="setup"></a>Setting up the mailer

The general steps to set up the mailer are:

1. Install Cloud Custodian locally
2. Create an SQS queue
3. (optional) Create an SNS topic
4. Create an IAM role
5. Create a `mailer.yml` file
6. Deploy the mailer
7. Add notify actions to policies

Detailed instructions for each step are below.

### Install Cloud Custodian locally

First, clone the repo to your machine:
`git clone https://github.com/capitalone/cloud-custodian`

Then, install dependencies and extensions:

```bash
virtualenv c7n_mailer
source c7n_mailer/bin/activate
cd tools/c7n_mailer
pip install -r requirements.txt
python setup.py develop
```

### Create an SQS queue

Create an SQS queue; it's helpful to name it something like `cloud-custodian-mailer` so you can find it later. Note the ARN and the URL of the queue.

### Create an SNS topic

If you'd like to send notifications to an SNS topic, create one now. Again, make note of the ARN - you'll need it later.

### Verify your email in SES

Choose the email you want to use as the "from" email address, and [verify](https://docs.aws.amazon.com/ses/latest/DeveloperGuide/verify-email-addresses.html) it in SES. It's worth noting that SES is only available in `us-east-1` (N. Virginia), `us-west-2` (Oregon), and `eu-west-1` (Ireland). Your SES setup can be in a different region than your mailer Lambda function; just make note of which region it is, and we'll configure it later in the `mailer.yml` file.

It's important to note that SES is kept in "sandbox" mode in an account until requested otherwise. While in "sandbox" mode, you will have to verify every recipient. When you are ready to be taken out of "sandbox" mode, follow these instructions to be [taken out of sandbox mode](https://docs.aws.amazon.com/ses/latest/DeveloperGuide/request-production-access.html).

### Create an IAM Role

The Lambda function created by the mailer will need permissions to access CloudWatch (logs and metrics), the SQS queue, the SNS topic (if you're using one), and SES (for sending emails). Use the SQS queue ARN and the SNS topic ARN in your policy, so the lambda can only access these specific resources. A sample policy for an IAM role is in the `mailerIAMPolicy.json` file in this repo. Create a role, attach a policy with these permissions, and make note of the role ARN.

### Create a mailer.yml file

The mailer is configured via a mailer.yml file. To send email via SES, your mailer config will look something like this:

```yml
queue_url: https://sqs.us-west-2.amazonaws.com/{accountId}/cloud-custodian-mailer
role: arn:aws:iam::{accountId}:role/cloud-custodian-mailer
from_address: test@example.com
region: us-west-2
ses_region: us-west-2
```

- `queue_url` (required) is the URL for the SQS queue you created earlier
- `role` (required) is the ARN of the IAM role that will be assumed by the Lambda function
- `from_address` is the email address that will be used as the `from` address by SES
- `region` is the region in which the mailer Lambda will be deployed
- `ses_region` is the region in which you've verified that `from` email address with SES
- `debug` is an optional property. Add this and set it to `True` if you wish to see debug-level logs.

### Deploy the mailer

Everything is set up, you have the configurations in order...time to deploy the mailer as a Lambda function! Run:

`c7n-mailer --config mailer.yml --update-lambda`

And a mailer Lambda will be created. If you need to update your mailer Lambda, simply run that command again. If you need more detailed output from the running Lambda's logs, a `--debug` flag is also available.

### Add notify actions to a policy

Now that the mailer is up and running, you can configure your Cloud Custodian policies to send notifications to it. Here's an example of a policy containing a notification action:

```yml
  # mark instances older than 30 days for termination; send email
  - name: ec2-old-instances-mark-for-termination
    resource: ec2
    mode:
      type: periodic
      role: arn:aws:iam::{account_id}:role/cloud-custodian-ec2
      schedule: "rate(1 day)"
    filters:
      - type: instance-age
        op: gte
        days: 30
      - "tag:KeepAlive": absent
      - "tag:maid_status": absent
      - "tag:Custodian": present
    actions:
      - type: mark-for-op
        op: terminate
        days: 4
      - type: notify
        template: default
        subject: 'These resources will be deleted in 4 days unless you add a KeepAlive tag'
        to:
          - resource-owner
          - team@company.com
        transport:
          type: sqs
          queue: https://sqs.us-west-2.amazonaws.com/{accountId}/cloud-custodian-mailer
```

The above policy finds any instance older than 30 days that doesn't have a `KeepAlive` tag or a `maid_status` tag. (Resources acquire a `maid_status` tag when Cloud Custodian has marked them for a later operation.) It then takes two actions against those resources:

- Marks those instances for deletion in 4 days
- Sends a message to an SQS queue. The message contents include a list of notification targets (e.g. emails, SNS topics, etc.), a subject, and the list of filtered resources.

Here's the fields typically found in a `notify` action:

- `type: notify` - this is required to create a notify action
- `template` - the resulting emails can use any number of preformatted templates. You can also create your own; see the "Writing a Template" section of the [docs](https://github.com/capitalone/cloud-custodian/tree/master/tools/c7n_mailer) for instructions on how to do this. Here, we're using the default template that comes with Cloud Custodian.
- `to` - here, specify a list of notification targets. Values in the list can be...
  - an email address
  - an SNS topic
  - a Datadog Metric
  - `resource-owner`. If this value is given, Cloud Custodian will look for an `OwnerContact` tag on the resource; that tag should contain a valid email.
- `transport` - transport has two properties in our situation. They are:
  - `type` - this should be `sqs`
  - `queue` - URL of the destination SQS queue

It's worth noting that notifications can also be sent via Slack or as Datadog Metrics. For more implementation instructions, read the [docs](https://github.com/capitalone/cloud-custodian/tree/master/tools/c7n_mailer).
