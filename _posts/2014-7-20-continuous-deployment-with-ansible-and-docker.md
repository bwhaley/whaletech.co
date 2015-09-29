---
layout: post
title: "Continuous Deployment with Ansible and Docker"
excerpt: |
  <p>Update 3/30/2015: I've since made improvements to this method and documented them in a <a href="https://www.whaletech.co/2015/03/29/deploying-to-aws-using-ansible-docker-and-teamcity.html">new blog post</a>. But there's still some valuable stuff here!</p>
  <p>I recently closed the loop on a continuous deployment p...
modified: 2015-3-30
comments: true
tags: [ansible, docker, continuous-deployment, aws, teamcity]
---
Update 3/30/2015: I've since made improvements to this method and documented them in a [new blog post](https://www.whaletech.co/2015/03/29/deploying-to-aws-using-ansible-docker-and-teamcity.html). But there's still some valuable stuff here!

I recently closed the loop on a continuous deployment pipeline and it feels like magic. Code runs in an integration environment within 5-10 minutes of a commit, thoroughly tested with unit tests and without downtime thanks to a rolling release process. Here's how I did it.

The system is built using the following technologies:
* Ansible, for configuration management and orchestration
* Docker, for shipping application code
* TeamCity, the build server
* GitHub for version control
* A custom-built AWS CloudFormation tool using Python and Boto

The service we're deploying is written in Go, but thanks to Docker this works equally well for any other language. I will adopt the same process for our Python-based services next.

The flow looks like this:

<figure>
<a href="https://i.imgur.com/j78u9Mv.png"><img src="https://i.imgur.com/j78u9Mv.png"></a>
</figure>

1. TeamCity polls GitHub for new commits on the integration branch
2. A build begins when a new commit is found
  * Get dependencies
  * Run unit tests
  * Build application binary
  * Build Docker container and push to the Docker Hub
  * Kick off deployment
3. The deployment process uses the CloudFormation tool for resource discovery and Ansible for coordinating the release
  * Send a release notification to a Hipchat room
  * Query the CloudFormation tool to find the systems and load balancers required for the release
  * Suspend autoscaling actions and disable alerting of the involved systems
  * SSH to the bastion host (more on this below) and kick off Ansible
  * Using Ansible's [EC2 dynamic inventory](https://docs.ansible.com/intro_dynamic_inventory.html), find the relevant application servers by tag
  * On one application server at a time:
    * Remove a server from the ELB
    * Stop the currently running Docker container
    * Pull the new container from the Docker Hub and start it
    * Add the server to the ELB
  * Resume autoscaling actions, resume alerting
  * Send a release success notification to Hipchat

If at any time the release fails, a notification is sent to Hipchat.

But the devil is in the details, of course.

## The Network
The first obstacle I had to overcome was how the build server could access systems in the network for deployment. As discussed in some detail in [this slide deck](https://speakerdeck.com/bwhaley/aws-design-patterns-at-anki), I run all my services in *micronet*; a single purpose VPC that confines a service to its own network. This is excellent for security isolation - a compromise of one application would be limited in scope to only the application's resources  - but the tradeoff is accessibility. The only exposure to the application servers is through a bastion host, which is open only to a single whitelisted IP address (the office). Running commands on those application servers would thus need to either jump through the bastion, or be run on the bastion itself.

<figure>
<a href="https://i.imgur.com/LWALf81.png"><img src="https://i.imgur.com/LWALf81.png"></a>
</figure>

The build server must know what bastion to use. This is accomplished by using [TeamCity build parameters](https://confluence.jetbrains.com/display/TCD8/Configuring+Build+Parameters). I configured the relevant parameters for the build server to dynamically find the bastion server and the ELB name via the custom Cloudformation tool. I configured a *deploy* user on the bastion servers and added an SSH key pair. The build server can SSH to the bastion as the deploy user to run Ansible commands.

## The CloudFormation Tool
I've long struggled with addressing infrastructure in a meaningful way. Drawing heavily from [The Twelve-Factor App](https://12factor.net/), I wrote a Python Flask application that organizes infrastructure in to *stacks* of backing resources, such as the VPC, the NAT server, databases, caches, queues, and so on.

On top of stacks I layer *releases*, which are the runtime resources of the application: instances and load balancers. Multiple releases can exist for a stack. For example, a service may have a data ingest application, a data query application, and a reporting application, all using the same backing resources.

Furthermore, it is common to need multiple environments for the same services: a development environment, testing or staging, and production. In my tool I use the term *deployment* to describe environments.

When the build server needs to deploy a new container, it consults this CloudFormation tool using `curl` and retrieves the bastion server and the load balancer. Once equipped with that data, another script can start the release. The build server connects to the appropriate bastion using `SSH` and runs Ansible with all the relevant parameters: the container to release, the instances to deploy to, and the load balancer to manage.

## Docker
Applications are deployed using Docker containers. This is very simple in the case of using Go since the application is a fully self-contained binary, and the base Docker image is just [Busybox](https://www.busybox.net/). Strictly speaking, Docker probably doesn't add a lot in this circumstance; I could just as easily copy the binary to each server and run it natively on the OS. Yet it does offer isolation from the rest of the system, and it keeps a uniform deployment system for other services written in Python or Ruby that have more complex dependencies.

The build server has Docker installed and builds the image from a Dockerfile in the root of the service's github repo. Once the image is built it is tagged with the name of the branch and pushed to the Docker Hub. At deploy time, each instance running the services logs in to the Docker Hub (using ansible) and pulls the new image. Ansible also starts the container with the pertinent environment variables, ports, and volumes.

While there are other Docker private registry services available, I chose the Docker Hub since it's currently the sole product offered by Docker, Inc, and I certainly benefit tremendously from their contributions to open source.

Importantly, as described in detail in my [StackOverflow answer](https://stackoverflow.com/questions/24807557/how-to-ship-logs-in-a-microservice-architecture-with-docker/24808726#24808726), I like to mount the syslog socket of the host to the container using `docker run -v /dev/log:/dev/log`. I configure rsyslog on the host to forward logs to a central collector service ([Sumo Logic](https://sumologic.com). After trying a number of different approaches such as running syslog within the container, using `docker logs`, and toying with the container's stdout log file on the host, I find that the bind mount of the host's syslog socket to be the best way to manage logs in the container.

## Enter Ansible
Ansible is used to build instances when the first launch and to orchestrate deployments. Thanks to the [Ansible Vault](https://docs.ansible.com/playbooks_vault.html), I store all configuration data in  the Ansible repo. Ansible also has [Docker](https://docs.ansible.com/docker_module.html) and [ELB](https://docs.ansible.com/ec2_elb_module.html) modules. The deployment playbook looks like this:

{% highlight yaml %}
# Build host groups from variables passed on the CLI
# This deploy playbook can be used globally on all hosts
# Hosts are limited using `ansible-playbook -l`
- hosts: all
  # Only run tasks on one host at a time
  serial: 1
  pre_tasks:
    # TODO: Disable alerts
    # TODO: Send deploy event
    # TODO: Disable autoscaling
    # These dynamic groups are created from variables passed on the ansible command line
   - name: Create dynamic groups from stack
     group_by: key={{ stack }}
   - name: Create dynamic groups from release
     group_by: key={{ release }}
   - name: Create dynamic groups from deployment
     group_by: key={{ deployment }}
   - name: Gather EC2 Metadata as facts
     action: ec2_facts
    # Remove the instance from all the ELBs it is registered to (usually just 1)
    - name: Deregister instance from ELB
      local_action: ec2_elb
      args:
        instance_id: "{{ ansible_ec2_instance_id }}"
        state: 'absent'
        region: 'us-west-2'
      # Stop the "live" container
    - name: Stop running container
      docker: image={{docker_image}} name=live state=absent
  roles:
    - { role: deploy, docker_env: '{{ my_environment }}', when: release == "myservice" }
  post_tasks:
    # TODO: Run smoke/sanity tests
    # Register the instances to the passed ELB names
    - name: Re-register instance
      local_action: ec2_elb
      args:
        instance_id: "{{ ansible_ec2_instance_id }}"
        ec2_elbs: "{{ item }}"
        state: 'present'
        region: {{ region }}
        wait_timeout: 30
      with_items: elb_names
    # TODO: Enable stackdriver alerts
    # TODO: Enable autoscaling
{% endhighlight %}

There are some placeholders for items that are either currently handled elsewhere or still need to be completed.

## Personal deployments
TeamCity has a novel feature called a [personal build](https://confluence.jetbrains.com/display/TCD8/Personal+Build). A developer can push branch with a known syntax, such as `remote-run/ben/my_feature`, and TeamCity will build it. By using this feature I'm able to provide developers with a private deployment to the cloud. I parse the branch for the username using `grep` in a build step, then release code to a known environment for that user. In this way, each developer can have an environment that *exactly* mimics production before it ever integrates with other code.

## Improvements
I have a bunch of improvements planned for the coming weeks:

* There is not enough testing in the current pipeline. In particular there is no integration tests. Continuous deployment without testing is a disaster waiting to happen. This is the first thing that needs attention in this model.
* The build server should not log in to the bastion. Instead, the build server will put a message in a queue. I'll write a queue worker that watches the queue for messages that kick off a release. Decoupling FTW.
* I currently only release to integration, not production. Mostly because of the lack of complete testing. This will be hooked up to production once I'm comfortable with the status of testing.

It feels damn good to have this low friction release process in place.
