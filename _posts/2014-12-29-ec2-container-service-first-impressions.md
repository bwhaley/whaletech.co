---
layout: post
title: "EC2 Container Service Hands On"


excerpt: "<p>I signed up for access to ECS when it was announced at reInvent, but didn't get in to the preview until December 18. I spent the past week kicking back and watching Anki's data ingest pipeline handle the insane Christmas traffic, and now that we're stabilized I've had a chance to take ECS for a spin. Here are some notes and observations about my experience using it for the first time.</p"
modified: 2014-12-29
comments: true
tags: [containers, ecs, docker, ec2, aws]
---
#### Please note: ECS has undergone major updates since this post! See the latest [from AWS](https://aws.amazon.com/ecs/).

I signed up for access to ECS when it was announced at reInvent, but didn't get in to the preview until December 18. I spent the past week kicking back and watching Anki's data ingest pipeline handle the insane Christmas traffic, and now that we're stabilized I've had a chance to take ECS for a spin. Here are some notes and observations about my experience using it for the first time.

The service can be described most simply as follows:

1. Create a cluster of one or more EC2 instances that run an ECS agent.
2. Register task definitions that describe what containers to run and how to run them
3. Run tasks on the cluster

The ECS API is a coordination service that stores the task definitions and runs tasks on the compute cluster. It also tracks the state of each instance, like how many and which containers are running, and the status of the tasks that run on the cluster over time.

Simple enough to describe, but can it be used to build a robust infrastructure?  

## Setting Up
I started with the AWS docs on [Setting Up](http://docs.aws.amazon.com/AmazonECS/latest/developerguide/get-set-up-for-amazon-ecs.html). I breezed past the boilerplate at the beginning, pausing only to create the IAM role for the container instances to assume. The only interface to ECS currently is via a preview version of the CLI tool; there's no console.
{% highlight bash %}
# Installing the CLI tool on a Mac
$ curl https://s3.amazonaws.com/ecs-preview-docs/amazon-ecs-cli-preview.tar.gz | tar xfvz -
$ cd amazon-ecs-cli-preview/awscli-bundle/ && python ./install
[snip]
{% endhighlight %}
After installing the CLI, I launched two instances in the default cluster using the pre-baked ECS image, which is based on Amazon Linux. It is also possible to [run the agent on your own instances and AMIs](http://docs.aws.amazon.com/AmazonECS/latest/developerguide/ECS_agent.html). When the instances came online I ran `aws ecs list-container-instances`, which showed the IDs as described in the docs.

## The Agent
I logged in and started looking around, starting with `/etc/ecs/` since it's mentioned in the docs. The agent configuration and an init script to start the agent live there. The init script downloads the agent's Docker image, if necessary, and runs the agent as container on the instance. The image is downloaded as a tarball and imported to the docker daemon using `docker load` rather than being pulled from a registry.

The agent is written in Go and is [open source](https://github.com/aws/amazon-ecs-agent). The runtime is a single static binary with a Docker image that's only 7MB: the size of the agent binary plus the [official scratch image](https://registry.hub.docker.com/_/scratch/) and an SSL certificate store to trust.

It's a very clean model for running an agent and one that I'd love to see more vendors adopt. A docker registry isn't needed because the image is so small. The agent opens a websocket connection to AWS to poll for updates, so it doesn't even expose any ports on the network. It doesn't require any credentials beyond the instance's IAM role. On the instance you can query the agent on localhost to find the cluster and instance identifiers:

{% highlight bash %}
$ curl localhost:51678/v1/metadata|./jq '.'
{% endhighlight %}
{% highlight json %}
{
  "ClusterArn": "arn:aws:ecs:us-east-1:792379844846:cluster/default",
  "ContainerInstanceArn": "arn:aws:ecs:us-east-1:792379844846:container-instance/90ccf398-f371-432d-b832-052c4daf2357"
}
{% endhighlight %}

Logs are available in `/var/log/ecs/`. That's the best place to look when troubleshooting a problem with the agent or with the tasks that it's running.

## Tasks
Apps must be described in order to run as Docker containers on an ECS cluster. This is done with **task definitions**, which are json-formatted descriptions of how to run containers. They include parameters such as the image to use, ports to expose, environment variables, and a name for the container (refer to the [complete list of parameters](http://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_defintions.html)). A **task** is the runtime invocation of a task definition. So you create the task definition, then run it as a task on the cluster. The API communicates with the agents about tasks via the aforementioned websocket connection.

ECS uses the term **family** to describe a series of related task definitions. Over time the definition may change. If you needed to change an env var, for example, or to expose a new port, you'd register a revision to the same family. Each revision can be invoked to run on the cluster.

Here's a simple sample definition from the docs. It runs sleep for 6 minutes in a busybox container:
{% highlight json %}
[
  {
    "environment": [],
    "name": "sleep",
    "image": "busybox",
    "cpu": 10,
    "portMappings": [],
    "entryPoint": [
      "/bin/sh"
    ],
    "memory": 10,
    "command": [
      "sleep",
      "360"
    ],
    "essential": true
  }
]
{% endhighlight %}

Notably absent from the parameter list is volumes, an important feature for mapping files from the host to the container and for sharing storage among containers. I'll go out on a limb by claiming that volumes are *so* fundamental to working with Docker that it must be near the top of the feature priority list internally at AWS. When combined with the ability to snapshot and attach/detach EBS volumes this could be very useful.

### Running tasks
The ECS API offers two methods to run a container.
{% highlight bash %}
# Allow ECS to place the container in the cluster
$ ecs --region us-east-1 run-task --task-definition sleep360:4 --count 1
# Specify an instance on which to run the container
$ ecs --region us-east-1 start-task --task-definition sleep360:4 --container-instances 90ccf398-f371-432d-b832-052c4daf2357
{% endhighlight %}
The docs state the difference between `run-task` and `start-task`.

> [Of `run-task`] Start a task using random placement and the default Amazon ECS scheduler. If you want to use your own scheduler or place a task on  a  specific container instance, use `start-task` instead.

Upon issuing the start or run command, the containers start more or less instantly if docker has the image for the container it needs to run. It will pull the image from a registry if it does not already exist locally. The task definition spec does not have a parameter for username and password to use for a remote registry, but you could work around this by seeding the image with those credentials.

The API exposes the information you'd expect about tasks, such as `list-tasks` and `describe-tasks`. You can describe tasks after they're finished but you can't restart them. You also don't have access to logs, but you can see the exit code of containers.

### Resource Control
ECS is capable of managing CPU and memory resources across the cluster. A CPU core is divided into 1024 **units**, which can be individually assigned to tasks. If you try to run a task that consumes more resources than are available, ECS returns an error.

{% highlight json %}
{
    "failures": [
        {
            "reason": "RESOURCE:CPU",
            "arn": "arn:aws:ecs:us-east-1:792379844846:container-instance/90ccf398-f371-432d-b832-052c4daf2357"
        },
        {
            "reason": "RESOURCE:CPU",
            "arn": "arn:aws:ecs:us-east-1:792379844846:container-instance/aa5436f9-1759-4d93-9822-704ebe761d48"
        }
    ],
    "tasks": []
}
{% endhighlight %}

Presumably we'll see more smarts added to this scheduler over time.

# Summing It All Up
If you're like me you may have skipped straight to the end past all the details. That's okay. If you're not like me and you read it all, then please send me your corrections rather than simply muttering under your breath about my mistakes!

My first reaction after reading and experimenting was, "that's it?", but upon further reflection I'm convinced this is a very nice start. If the goal is to have a managed layer of compute capacity that can run application code in a resilient, secure, repeatable fashion, this platform shows a lot of promise in its simplicity. It exposes just a few primitives: clusters of compute, instances within clusters, and tasks to run. From these pieces it's possible to assemble a larger system.

What I like best is that it's not a complete black box like PaaS offerings. The OS image can be managed manually, the instance types can be customized, the entire OS environment is controllable. If I want to run Logspout on every instance myself I can do that. I can even distribute the compute as I like throughout the network. There can be deep integration with orchestration tools to compose complex inter-related systems.

But it doesn't feel done yet.

* There is no native integration with Autoscaling or ELBs.
* ECS really should handle the compute on its own, even if it doesn't control the machine image and OS. If there's not enough capacity for the tasks I've specified, or if there's more than enough, handle it.
* There's no support for restart policy and various other Docker features. Did I already mention volumes?
* I'd love to see integration with KMS for the potentially sensitive variable data that's part of the task definition, or better yet combine it with DynamoDB for a service registry.
* How do I keep an eye on my containers? ECS doesn't seem to send any kind of notification to SNS if a container fails. I shouldn't have to monitor this myself.

There's also no registry service and Amazon doesn't appear to have plans to create one. During the announcement at reInvent they made it clear that they're partners with Docker and the Docker Hub. It's too bad because it would be great to have a managed, private registry that was super fast and had a web interface suitable for human use.

I haven't used it in anger yet, but I'm excited to see how this service continues to shape up.
