---
layout: post
title: "AWS re:Invent 2014: Initial Reactions to Aurora, KMS, & Code*"
excerpt: |
  <p>This is a continuation of <a href="https://www.whaletech.co/2014/11/16/aws-reinvent-2014-initial-reactions-to-aurora-kms-code.html">my previous 'Initial Reactions' post</a> on the EC2 Container Service and Lambda. </p>
modified: 2014-11-16
comments: true
tags: [reinvent, aws]
---
This is a continuation of [my previous 'Initial Reactions' post](https://www.whaletech.co/2014/11/16/aws-reinvent-2014-initial-reactions-to-aurora-kms-code.html) on the EC2 Container Service and Lambda.

## [Aurora](https:://aws.amazon.com/rds/aurora/)
RDS for Aurora is an RDBMS focused on adding the features of enterprise databases to the simplicity of the widely-used MySQL engine. AWS touts the service as being performant, scalable, durable, secure, and inexpensive. It is the fifth RDS database engine, following the addition of PostgreSQL, which launched at reInvent 2013.

Like MySQL and PostgreSQL, Aurora supports replication, but through a custom clustering mechanism. The [documentation](https:://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Aurora.html) describes the architecture as one or more instances with a cluster volume, which is a virtual storage volume that spans multiple availability zones.

<figure>
<a href="https:://i.imgur.com/tFj349Z.png"><img src="https:://i.imgur.com/tFj349Z.png"></a>
</figure>

Jeff Barr notes in his [blog post announcing Aurora](https:s://aws.amazon.com/blogs/aws/highly-scalable-mysql-compat-rds-db-engine/), and Anura Gupta [confirms via Twitter](https:s://twitter.com/awgupta/status/533777613836148736), that data is written by the master six times, two times each in three availability zones. A quorum of writes (four of the six) must succeed before Aurora accepts the data as durable. Read replicas share the data volume with the primary, and as such provide exceptionally low replica lag.

Unlike with MySQL and Postgres, backups in Aurora are incremental and continuous. The documentation claims that backups can be restored with 1-second granularity and the most recent backup is typically within the past 5 minutes. Quite an improvement over the once-daily snapshots for other RDS backup engines.

If history is any guide, AWS can expect rapid adoption of its new database service. Since Aurora is MySQL 5.6 compatible and has the same pricing structure, it's a no brainer for developers to try it first.

Some users will cry "lock-in" and avoid Aurora. Those users are missing the point of AWS.

## [CodeCommit](https:://aws.amazon.com/codecommit), [CodePipeline](https:://aws.amazon.com/codepipeline), and [CodeDeploy](https:://aws.amazon.com/codedeploy)
CodeDeploy is a long overdue service that automates software deployments to EC2 instances. The deployment process involves notifying CodeDeploy about a new application revision by telling it where to find the deployment artifacts in GitHub or S3. CodeDeploy then contacts an agent on the instances and coordinates a zero downtime release. Users provide a YAML-formatted [AppSpec file](https:://docs.aws.amazon.com/codedeploy/latest/userguide/app-spec-ref.html) that defines file locations, permissions, and hooks to run in response to various states of deployment. It integrates with all the services you'd expect: CI systems like Jenkins, CircleCI, and TravisCI, and Config Management systems like Ansible, Chef, Puppet and Salt. Known internally at Amazon as *Apollo*, the service deploys code 50,000,000 times per year, or 95 times per minute across Amazon. It's used by 90% of teams internally.

I've solved this problem many times over with various Ops teams. It has always been a trial and error process that is heavily customized based on the team's toolchain, skill set, and preferences. It's nice to see some standardization brought to the process.

Still, I'll be skeptical of some of the decisions until I run it myself. It's never ideal to have Yet Another Agent on instances. Also, Netflix has established what can be considered a best practice for zero downtime release, which involves autoscale group replacement. Netflix's record for quality and high availability is recognized as the best in the industry, and a change to the rolling upgrade process used by CodeDeploy is a big difference. But if it works for AWS it will work for many others as well.

CodeCommit is a managed Git source control service, and CodePipeline is a continuous delivery platform. Both are not yet in preview and details are light. Apparently the services can either integrate with existing services in this space (GitHub/BitBucket/etc for CodeCommit, Jenkins/TeamCity/TravisCI for CodePipelines) or can serve as standalone tools.

This trifecta of source control, release pipeline, and deployment should be refreshing for any Ops team who uses AWS. It closes the loop for managing code releases which has long been a sore point.

## [Key Management Service](https:://aws.amazon.com/https:s://aws.amazon.com/kms/)
AWS KMS is a highly secure managed service for handling cryptographic keys used for encrypting data. It transparently handles key creation and deletion, rotation, and auditing. Keys are stored safely in HSM, a service that is not economically feasible (and is often overkill) for many AWS customers.

As an Ops professional and sys admin, key management is something I've struggled with for years. Distributing credentials turns out to actually be a hard problem, and one that is ignored or inadequately solved by most existing tools. I believe KMS to be the unsung hero of this year's reInvent conference and can dramatically improve the operational security posture for web services.

Take configuration management as an example. The [Ansible Vault](https:://docs.ansible.com/playbooks_vault.html) and the [Chef Vault](https:s://github.com/Nordstrom/chef-vault) both attempt to solve the problem of distrubuting sensitive data by encrypting it and storing it alongside the config management code. The client is responsible for decrypting at run time. But how does one distribute the decryption key to the clients in a secure manner? It must live in plaintext somewhere: on the filesystem with restrictive permissions, perhaps, or by using the existing asymmetric key pair in the case of Chef Vault. The Puppet solution is more complex and less integrated than either of these.

KMS can help with this. The data can be encrypted and decrypted using KMS data keys. Instances can be assigned IAM roles with permission to request the decryption key from KMS. The plaintext decryption key need not be stored at all. I expect to build many services in a far more secure manner thanks to the ability to simply and easily manage encryption & decryption keys.

##Wrapping Up
This is of course an incomplete treatment of the new services, and ignores several of the new enterprise services: AWS Service Catalog and AWS Config. I can only digest so much at a time.

The rapid pace of development within AWS is staggering. The keynote stated that AWS will release 500 features, services and improvements in 2014, more than double last year's pace. I've had the experience several times this year of waking up to a refreshing email from AWS that solved a problem that I was just considering how to handle. This is why it's such a pleasure working on the platform; always something new to learn and explore.
