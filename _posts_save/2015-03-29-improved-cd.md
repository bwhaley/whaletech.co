---
layout: post
title: Improved continuous deployment using Ansible, Docker, SQS and TeamCity
excerpt: "It hasn't even been a full year yet since my last post on continuous deployment and I've already reimplemented a more robust system. This post covers the challenges I had with that previous iteration, then the design and implementation of the new deployment platform. I hope you'll find it useful."
modified: 2015-03-29
tags: [sqs, ansible, docker, vpc]
comments: true
---
It hasn't even been a full year yet since [my last post on continuous deployment](http://blog.bwhaley.com/continuous-deployment-with-ansible-and-docker) and I've already reimplemented a more robust system. This post covers the challenges I had with that previous iteration, then the design and implementation of the new deployment platform. I hope you'll find it useful.

### Take One

My last attempt at building a CD system with Ansible, Docker and Teamcity has a few fatal flaws that renders it difficult to work with:

1. I had written a custom tool that used AWS CloudFormation to create resources, then later searched those resources. This suffered from the typical "built in house" problem; it was poorly documented and maintained, and only I understood it. It was difficult to justify its place in the design and it didn't scale well with a larger team.
2. The *micronet* concept was nice for security but overall too much of a burden. When running even a modest number of services, say 15-20, I found that the overhead of a dedicated VPC (including a NAT and a Bastion) per service was expensive and difficult to manage. Moreover, tools today expect that IP addresses are unique, and my VPC address spaces overlapped, causing a number of subtle errors.
3. The rolling deployment model is fraught with peril. Sometimes instance registration/deregistration with the ELB mysteriously failed, and no amount of Google Fu could uncover the problem. It has the side effect of long-lived servers that are never patched.

For these reasons I opted to try a new approach. A sort of custom, naive implementation of a self-sufficient scheduler.

### Building Blocks
I like to say that security and administration start from the network. I had already [designed a new network](http://blog.bwhaley.com/reference-vpc-architecture) to remove the duplication and overhead incurred by the micronet concept. If you read and understand that post this one will make a lot more sense. In the new network I had a single bastion host in a dedicated management network that is peered to separate test and production networks. The bastion is the only point of entry to the environment other than the public facing web servers or ELBs, and this made it simpler to interact with the environment externally.

I considered tools such as [Netflix's Asgard](https://github.com/Netflix/asgard) that release new code by replacing launch configurations and autoscale groups (read up [here](http://docs.aws.amazon.com/AutoScaling/latest/DeveloperGuide/GettingStartedTutorial.html) if you don't know about this). This approach is appealing but I wasn't excited about introducing a complex java application that I didn't understand (I'm sure the Netflix folks out there would beg to differ). So rather than implement Asgard, I set about recreating some of its functionality using Ansible.

Ansible has great integration with AWS, with modules available for EC2, S3, Autoscaling, CloudWatch, ELB, EBS volumes, Route53, and more. Some argue that deployment is a complex operation requiring a stateful system. They're probably right, and in that case Ansible doesn't quite fit the bill, but I decided I could sacrifice some features that could be enabled by a stateful system to simplify the process.

I've enjoyed working with Docker in production environments since around version 0.5. I've had my fair share of challenges with it, documented elsewhere on this blog. I tend to run a single container per host. Sometimes people ask me, "What's the point? Just run your app native on the OS." I like the isolation and the uniform deployment that it offers. Every app is just a container and an image. The underlying host is just the same.

I stuck with TeamCity. I like the templates and the subprojects. I find the interface clean and easy to navigate. I like the real time build log that shows the status of builds (and deploys) as they happen. I wish it wasn't in Java, but the install process mostly gets out of the way. Once it's set up it just works.

### TeamCity Build Configurations and Docker Images
The first step in deployment is actually having software ready to deploy. Thus, the genesis of a deployment is a commit. The [git flow model](https://www.atlassian.com/git/tutorials/comparing-workflows/gitflow-workflow) works nicely with continuous deployment. In my case, TeamCity polls certain Github branches for a commit. When a commit is detected on one of the monitored branches, the build is triggered. Deployment is part of the same build process in my case, but it could also be triggered by the completion of a successful build.

Which branches to poll becomes an important consideration. I like to have one branch per environment in each repository that is continuously deployed. For example, the branches might be develop, stage, and master. When new code is ready, the developer merges code first to develop and pushes to Github. The build runs the tests, builds a docker image, and the final step releases the code to a development environment in AWS. The same code can be released to a staging and production environment by simple git merges.

TeamCity build configs have parameters so that builds can be reused by multiple projects. I use these parameters to identify the *service* (e.g. the application) and the *environment*, as well as info about which docker repo to push builds to and the credentials to use.

The build artifact is a Docker image. There is a private repository on the Docker Hub for each service. Each image is tagged with the short git SHA from which that image was built using `docker build -t=<namespace>/<repo>:<git-short-sha> .`. In this way it is possible to build the image just one time and reuse the same Docker image in each environment.

Visually, the process looks something like this:

<figure class="half">
<img src="http://i.imgur.com/ZfqHLU9.jpg">
</figure>

The Docker registry API exposes the available tags associated with a repo. This bash snippet will check if an image with a given SHA already exists. The `%var%` variables are TeamCity syntax for build parameters.

{% highlight bash linenos %}
GIT_HASH_SHORT=$(/usr/bin/git log --abbrev-commit --pretty=oneline | /usr/bin/head -1|/usr/bin/awk '{print $1}')
DOCKER_INDEX=https://index.docker.io/v1/repositories/%docker_repo%/tags
curl -s --user %docker_hub_username%:%docker_hub_password% ${DOCKER_INDEX} | grep ${GIT_HASH_SHORT}
if [ $? -eq 0 ]
then
    echo "This tag already exists on the remote image repository; skipping this build"
    exit 0
fi
{% endhighlight %}

### Deployments using Ansible
Once the docker image exists, the final step in the TeamCity build process is to SSH to the bastion server and run an Ansible playbook. The playbook implements the blue/green deployment model in much the same way that Asgard does, [as documented in this post by CloudNative](https://cloudnative.io/blog/2015/02/the-dos-and-donts-of-bluegreen-deployment/). Step-by-step the process looks like this:

1. Find the current autoscaling group
2. Generate user data for instances in the new launch config
3. Create a new launch config, include the *service*, *env*, and *docker_tag* EC2 tags and using the user data from step 2
4. Create a new autoscaling group using the launch config from step 3
5. Wait for instances to come online and be healthy
6. Terminate the old autoscaling group using the info from step 1.

This assumes that it's okay for two versions of the app to be running simultaneously. Also, database schema migrations must be managed by the user - they're not magically handled somehow during this process.

I did [fight a few bugs](https://github.com/ansible/ansible-modules-core/issues/383) in the autoscaling module. In particular, the Ansible code that waits for instances to come online (step 5) was marking instances as healthy before they actually were. But things worked swimmingly once solving that pesky problem.

### Bootstrapping new instances
EC2 user data is a method to initialize instances. In chef or puppet, it might be used to run the agent against the server. You need to either allow auto signing of certificates to new servers or solve the auth problem in some other way. Using ansible, some people use [pull mode](http://www.stavros.io/posts/automated-large-scale-deployments-ansibles-pull-mo/).

I didn't want to have ansible on each instance. I use ansible vault to store sensitive config data like database credentials and API keys, and I didn't want the passphrase or any other secrets baked in to the image. So my bootstrap process is a little different. The user data for each instance in an autoscale group drops a message in an SQS queue indicating its IP address, service, environment, and Docker tag. A daemon on another host (I use the bastion) polls this queue, and runs Ansible on the instance when it boots. Like this:

<figure class="half">
<img src="http://i.imgur.com/KLd4U4U.jpg">
</figure>

This scales nicely, avoids keeping any sort of secret on the instances themselves, and can support many different services simultaneously. The `ansible-playbook ... myapp.yml` step can do all the necessary steps to provision an instance. In my case, this means pulling and running a docker image. It might mean running a few containers, or adding users and configuring NTP, or any number of other things. But the instance itself never needs ansible installed, nor any git repositories or private keys.

In order for instances to send messages to the queue they need to be part of an IAM role that allows access. I use an [IAM managed policy](http://docs.aws.amazon.com/IAM/latest/UserGuide/policies-managed-vs-inline.html) that looks like this:

{% highlight json %}
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Stmt1424212450000",
      "Effect": "Allow",
      "Action": [
        "sqs:SendMessage"
      ],
      "Resource": [
        "arn:aws:sqs:us-west-2:012345678901:deploy"
      ]
    }
  ]
}
{% endhighlight %}

I also bake the [AWS CLI tool](http://aws.amazon.com/cli/) in to the image to simplify sending the message.

### Wrapping up
I've [shared the code I use for this process on github](https://github.com/bwhaley/asg_deploy). it includes:

* An ansible role for replacing autoscale groups
* User data that will send a deployment message to SQS
* A python app for polling SQS and deserializing deploy messages. I run this on the bastion via supervisord.
* A bonus AWS resources role that I use to make sure ELBs and security groups exist before releasing an autoscaling group

The code is not well documented so contact me or leave a comment with any questions.
