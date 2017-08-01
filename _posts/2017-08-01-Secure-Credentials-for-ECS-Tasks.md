---
layout: post
title: "Secure credentials for ECS tasks using the EC2 Parameter Store"
excerpt: "In case you haven't been following along, AWS ECS has improved dramatically since my first hands-on experience with it back in 2014. While still not as fully featured and certainly not as pluggable as Kubernetes, I believe that ECS is now the best choice for most containerized workloads. The integration with other services (IAM, ALB, ECR) are hard to accomplish with any other system, and you're relieved of any and all cluster management. And I would wager that it's easier to get security right with ECS than with any other container scheduler."
modified: 2017-08-01
comments: true
tags: [AWS, EC2, Security]
---

In case you haven't been following along, [AWS ECS](https://aws.amazon.com/ecs/) has improved dramatically since [my first hands-on experience](https://www.whaletech.co/2014/12/29/ec2-container-service-first-impressions.html) with it back in 2014. While still not as fully featured and certainly not as pluggable as Kubernetes, I believe that ECS is now the best choice for most containerized workloads. The integration with other services (IAM, ALB, ECR) are hard to accomplish with any other system, and you're relieved of any and all cluster management. And I would wager that it's easier to get security right with ECS than with any other container scheduler.

Which brings us to the point of this post: secure credential handling. This is an area that has received a lot of attention recently, and long overdue in my opinion. In a nutshell, the problem is that apps need access to secrets (database credentials, keypairs, API tokens, etc) and we don't want these floating around in plain text. Excellent tools such as Hashicorp Vault, Credstash from Fugue, and Confidant from Lyft are a few of the leaders, and they're perfect general purpose credential management tools. AWS [recently added hierarchy support](https://aws.amazon.com/about-aws/whats-new/2017/06/amazon-ec2-systems-manager-adds-hierarchy-tagging-and-notification-support-for-parameter-store/) to the EC2 Parameter Store, opening the door to native AWS tooling for secure credential handling.

So, how does it work?

1. Add a new SecureString parameter to the Parameter Store
2. Use [IAM roles for ECS tasks](http://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-iam-roles.html) to permit ECS docker containers to read the parameters
3. At run time, load the parameters using the new [GetParametersByPath](http://docs.aws.amazon.com/systems-manager/latest/APIReference/API_GetParametersByPath.html) API to read the parameters in to the environment and invoke an application.

Here's an example for running Grafana as an ECS service, safely storing its database credentials in the Parameter Store. All Grafana configuration can be controlled [via environment variables](http://docs.grafana.org/installation/configuration/#using-environment-variables). We'll use the [aws-env tool from GitHub](https://github.com/Droplr/aws-env) to read the parameters to Grafana-compatible environment variables. I won't cover all the nitty gritty of creating the IAM role and policies. Refer to [this nice walkthrough](https://aws.amazon.com/blogs/compute/managing-secrets-for-amazon-ecs-applications-using-parameter-store-and-iam-roles-for-tasks/) that covers some of the same ground.

First we'll create parameters in the hierarchy. We can structure the hierarchy for multiple environments and applications like this:

{% highlight bash %}
/<environment>/<application>/<parameters>
{% endhighlight %}

In the case of Grafana, we can create the parameters like this:

{% highlight bash %}
$ password=$(openssl rand -base64 15)
$ aws ssm put-parameter \
    --name /prod/grafana/GF_DATABASE_USER \
    --type "SecureString" \
    --value 'grafana'
$ aws ssm put-parameter \
    --name /prod/grafana/GF_DATABASE_PASSWORD
    --type "SecureString"
    --value $password
$ aws ssm describe-parameters
{
    "Parameters": [
        {
            "LastModifiedUser": "arn:aws:iam::555513456271:user/ben",
            "LastModifiedDate": 1501549875.487,
            "KeyId": "alias/aws/ssm",
            "Type": "SecureString",
            "Name": "/management/grafana/GF_DATABASE_PASSWORD"
        },
        {
            "LastModifiedUser": "arn:aws:iam::555513456271:user/ben",
            "LastModifiedDate": 1501549860.718,
            "KeyId": "alias/aws/ssm",
            "Type": "SecureString",
            "Name": "/management/grafana/GF_DATABASE_USER"
        }
    ]
{% endhighlight %}

Since we didn't specify a KMS key, SSM defaults to the "aws/ssm" key.

We need our Grafana ECS task to have access to read the parameters. It's not clear from the documentation which exact permissions are needed. ssm:GetParametersByPath is not enough. I ended up with the following policy (partially snipped for clarity):

{% highlight json %}
{
    "Action": [
        "ssm:GetParameterHistory",
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath"
    ],
    "Resource": [
        "arn:aws:ssm:us-west-2:555513456271:parameter/prod/grafana*"
    ],
    "Effect": "Allow"
},
{
    "Action": [
        "kms:Decrypt"
    ],
    "Resource": [
        "arn:aws:kms:us-west-2:555513456271:key/36325f94-19b5-4649-84e0-978f5542aa0a"
    ],
    "Effect": "Allow"
}
{% endhighlight %}

The resource restriction in the SSM section limits Grafana to only accessing its portion of the hierarchy. Be as granular as possible here to limit the possibilty of one application reading the credentials intended for another.

Once the task has the appropriate permissions, use the aws-env tool to read the parameters at run time. Here's the Dockerfile I used for the Grafana image:

{% highlight bash %}
FROM grafana/grafana:master

RUN curl -L -o /bin/aws-env https://github.com/Droplr/aws-env/raw/master/bin/aws-env-linux-amd64 && \
  chmod +x /bin/aws-env

ENTRYPOINT ["/bin/bash", "-c", "eval $(/bin/aws-env) && /run.sh"]
{% endhighlight %}

Now each of the parameters are available as an environment variable in the container:

{% highlight bash %}
root@b2cb34da7ace:/# eval $(aws-env)
root@b2cb34da7ace:/# printenv | grep GF
GF_DATABASE_USER=grafana
GF_DATABASE_PASSWORD=abcd123EXAMPLEPASSWORD
{% endhighlight %}

Your custom application may need a wrapper to read the parameters from the environment variables.
