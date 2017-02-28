---
layout: post
title: "Evaluating Elastic Beanstalk, an Ops perspective"
excerpt: |
  <p>Much has been written on the topic of using a PaaS such as Heroku or Elastic Beanstalk for hosting web applications. The benefits are obvious: simpler deployment, hands-free hosting, implicit adherence to scalable web application programming patterns such as <a href="http://12factor.net/">The Twelve-Factor App</a>. But how does Elastic Beanstalk hold up when an application reaches a certain level of complexity? Do the aforementioned benefits outweigh the necessity of conforming to an operationally constrained environment? This post will relate a few challenges I encountered when evaluating AWS Elastic Beanstalk from an operations perspective.
modified: 2014-08-31
comments: true
tags: [aws, elastic-beanstalk]
---
#### Update: Since this post, AWS has integrated Elastic Beanstalk with its EC2 Container Service, addressing many of the concerns I express below regarding its Docker support. [See the docs on multicontainer Docker environments](http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/create_deploy_docker_ecs.html).

Much has been written on the topic of using a PaaS such as Heroku or Elastic Beanstalk for hosting web applications. The benefits are obvious: simpler deployment, hands-free hosting, implicit adherence to scalable web application programming patterns such as [The Twelve-Factor App](http://12factor.net/). But how does Elastic Beanstalk hold up when an application reaches a certain level of complexity? Do the aforementioned benefits outweigh the necessity of conforming to an operationally constrained environment? This post will relate a few challenges I encountered when evaluating [AWS Elastic Beanstalk](http://aws.amazon.com/elasticbeanstalk/) from an operations perspective.

The Application
---------------------
This evaluation was done on behalf of a client I do freelance Ops work for. It is a typical Rails application comprising a web server and four worker processes that handle delayed jobs and perform data processing and analysis. The application was built with Heroku in mind, and thus uses a [Procfile](https://devcenter.heroku.com/articles/procfile) to declare its processes. It conforms to many/most of the 12-Factor principles such as keeping configuration in the environment, logging to `STDOUT`, and concurrency.  

During the evaluation, I was also considering future expansion of the client's application environment. This is but one of several existing Rails applications, and the client of course has plans for future work. Our ideal solution would be a uniform platform for all applications.

The Evaluation
---------------------
Getting started with Beanstalk is straightforward. Create an application, create an environment. Upload an application version, then deploy it to an environment. That's about it, and I hit a snag right away.

I'm familiar with at least three zero downtime release procedures (these are discussed in more detail in my [Mobile Scale AWS](https://speakerdeck.com/bwhaley/mobile-scale-aws) slide deck):

1. Blue/Green deployment: Green environment is live, blue environment contains new application code. Once blue is up and tested and known to be operational, cut traffic over to blue and eventually decommission green. On AWS this is normally achieved with ELBs.
2. Rolling release, in which one instance at a time is removed from the ELB, upgraded, and added again.
3. A hybrid version in which another autoscale group with new code is registered to the same load balancer as the existing code. Once the new autoscale group is running with enough instances to handle the environment, the old group is decommissioned.

Of these three options, only the blue/green model is supported by Beanstalk, and it is IMO the least desirable. It requires a DNS change from one environment to the other. This introduces client DNS cache failure scenarios, and if it's a busy site, there's the added wrinkle of [pre-warming the new ELB](https://aws.amazon.com/articles/1636185810492479#pre-warming) that's attached to the new blue deployment. Beanstalk is not capable of rolling application version updates, nor the autoscale release model. So already I was starting to think about hacky work arounds to avoid the blue/green deployment structure. Not a great start.

The next challenge I encountered was around the application platform. Beanstalk supports several platforms natively: Java, .NET, Node, PHP, Ruby, etc. It also supports Docker, which means it really supports anything you throw at it. This was in fact one of the primary draws in considering Beanstalk to begin with. My preferred model was to write a Dockerfile to build the application image, create an AMI with that base image baked in, then start the appropriate process (web, delayed job worker, I/O worker, etc) from the `docker run` command.

I was very quickly disenchanted with the available Docker support. The Beanstalk approach is to either a) build the image and run the container from a Dockerfile located in an saved application bundle that Beanstalk knows about, or b) use the Beanstalk magic `Dockerrun.aws.json` file that describes an image on a public or private repository, including its volumes, ports, and logs. Beanstalk will extract the application bundle on an instance, build the Dockerfile, and run it.

But there is no control over the `docker run` command. There is no ability to [link containers](https://docs.docker.com/userguide/dockerlinks/) nor to run multiple containers on a host. Beanstalk users are also stuck using the supported versions, which may lag a bit behind, a serious problem when working with a fast moving project like Docker. I was able to run the application, including all its workers, within a single container, but this is not the preferred operational model. Strike two.

Next up: logging. Beanstalk has a [Logs](http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/using-features.loggingS3.title.html) feature that allows users to snapshot the last 100 lines of log files, or to download all log files or have them pushed to an S3 bucket. Simply put, this method of handling log data is inefficient at best. Developers are used to services like Papertrail that lets them view an aggregate stream of log data in real-time. Snapshotting 100 lines of 10+ log files and viewing them through a web console is a waste of time. I started searching on [integrating Papertrail and Beanstalk](http://help.papertrailapp.com/kb/hosting-services/aws-elastic-beanstalk/), but found that when combined with Docker it felt like a hack. We would really need to just write syslog support in to the app with [`remote_syslog`](http://help.papertrailapp.com/kb/configuration/configuring-centralized-logging-from-ruby-on-rails-apps/#remote_syslog) or similar. This is no big problem, but does violate the 12-factor app. It's just another case of the need to bend our operational and development methodology to the environment.

In summary, after perhaps my third evaluation of Elastic Beanstalk, I found it to be insufficient for even a reasonably simple application. It's lack of support for reasonable zero-downtime release procedures, coupled with incomplete Docker support, the inability to run multiple processes other than by using Beanstalk's limited [Worker Environment Tier](http://docs.aws.amazon.com/elasticbeanstalk/latest/dg/using-features-managing-env-tiers.html), and the hacky logging approach makes it unsuitable.

I'm disappointed. It's desirable to build an application environment that developers can operate without a lot of specialized domain knowledge. Heroku seems to be the best-of-breed PaaS, offering a lot of flexibility and very nice integration with partner SaaS vendors like New Relic, but ultimately costing more money and still not offering sufficient control.

My next step with this project is to evaluate OpsWorks and/or rolling a custom environment using Ansible. As an ops/admin/systems developer, I'm comfortable with this. But either will require significantly more commitment from developers to learn either Chef or Ansible and the associated release process with each. This is not ideal, not because the developers can't learn it (quite the opposite, they'll probably have many ideas for optimization), but rather that they must spend time on operations rather than on writing code that provides value to the business. Unfortunately, this seems to be the only model that affords enough control and customization.
