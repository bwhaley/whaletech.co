---
layout: post
title: "Tooling around with CloudFormation helpers"
excerpt: "Pretty much everybody can agree that working with CloudFormation is a bit, shall we say, cumbersome. Dare I attempt to recite its shortcomings? No, I dare not. Okay, maybe just a few..."
modified: 2017-02-28
comments: true
tags: [AWS, cloudformation]
---
Pretty much everybody can agree that working with CloudFormation is a bit, shall we say, cumbersome. Dare I attempt to recite its shortcomings? No, I dare not. Okay, maybe just a few:
* Until relatively recently, everything had to be done in JSON, which is terrible and allows no comments. Then AWS added YAML, which is better, but still a bit unwieldy.
* Working with multiple stacks with dependencies is downright painful. There is support for [cross-stack references](http://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/walkthrough-crossstackref.html), but that's also quite painful.
* Sharing configuration via parameters sucks.
* The workflow of creating a template, validating the syntax, submitting it to AWS, waiting for something to fail, rinse & repeat is horrendously time consuming.

All bets are off when you're trying to manage dozens of CF templates.

### So, Terraform
I know a bunch of people will be red in the face yelling at me to "Use Terraform! It's so much better! It will solve all your problems!"

I have the utmost respect for Hashicorp and their tooling. They've improved the situation for sys admins & devs & DevAdmins and all the other cloud people more than I can ever hope to. I <3 most of their tools. I went to a talk by Mitchell H just the other week at Nike. I learned stuff about graph theory and terraform.

I have tried to like terraform. I tried pretty hard about a year ago. It had some rough edges, and I understand that it has changed a lot since. But I still don't trust it. At the time of writing there are 1,613 open issues and 254 pull requests. One of the issues is [mine](https://github.com/hashicorp/terraform/issues/5006). It has been open since Feb. 4 2016. It's a pretty serious bug that causes EBS volumes to be unexpectedly deleted. A bunch of other people have +1'd the issue. Beyond labels, nobody on the Terraform team has even acknowledged it. One of the biggest benefits is the multi-provider support, which I don't need. I even checked it out again for this project and found that it doesn't have VPC IPv6 support yet. And dammit, CloudFormation _just works_ for me, so plz stop yelling at me about it.

### Fixing CloudFormation
I have some ideas to make CF a bit easier to work with, but I figured that before I built Yet Another Tool I should take a quick peek at what's out there already. Some searching revealed a few promising candidates:

* [StackMaster](https://github.com/envato/stack_master)
* [sceptre](https://github.com/cloudreach/sceptre) from CloudReach
* [Stacker](https://github.com/remind101/stacker) from Remind
* [qaz](https://github.com/daidokoro/qaz)

At first glance, qaz was really appealing because it's written in Go and attempts only a minimal abstraction over CloudFormation. But it's the brand new kid on the block and I need to use this sucker to manage production infrastructure, so I didn't kick the tires on it too much. It's definitely promising.

StackMaster supports diffs, change sets, and, enticingly, GPG parameter encryption. I like that stuff. But it's written in Ruby, and I get a higher dose of Ruby than I'd like with Chef. I tend to tune out when I see terms like SparkleFormation. I didn't necessarily want to learn another DSL, and the Ruby tooling (RVM, gem) makes me want to break keyboards. But for people that are better at Ruby than I am, this is probably a good choice.

Sceptre is on the minimalist end. You still need to write your own CF templates (in JSON or YAML). It provides simple wrappers for CRUD operations and presents a reasonable CLI. I want something with a bit more programmatic control and more features.

Enter Stacker, the tools that fits the bill for me. Python with Troposphere-based "blueprints" provide the full power of Python. A very intuitive, simple CLI with most of the features of StackMaster but without the Ruby. Plus it's from the team at Remind, and I've followed their work for some time now. (Check out [Empire](https://github.com/remind101/empire), you might like it.)

The rest of this post is about my experience getting started with Stacker.

## First steps with Stacker
Stacker has some [very nice docs](http://stacker.readthedocs.io/en/latest/) and [examples](https://github.com/remind101/stacker_blueprints) but nothing that serves as an introductory tutorial. The following is more or less my raw notes on getting using Stacker for the first time.

Obvious first step: install stacker and setup a work space

{% highlight bash %}
$ virtualenv stacker_venv
$ source stacker_venv/bin/activate
$ pip install --upgrade pip setuptools
$ pip install stacker
$ stacker --version
stacker 0.8.6
$ mkdir -p stacker/{blueprints,config/environments}
{% endhighlight %}

Now it's time to dive in to the deep end. I need to implement my [reference vpc architecture](https://whaletech.co/2014/10/02/reference-vpc-architecture.html) with just a few changes. Since that post, AWS released NAT gateways (beautiful, I'd been waiting for those suckers for years), and IPv6 support (even more beautiful because I want the Internet to continue to scale). I work best from examples, and I'm lazy, so I'm going to start with Remind's [VPC blueprint](https://github.com/remind101/stacker_blueprints/blob/master/stacker_blueprints/vpc.py).

1. Copy Remind's [vpc.py](https://github.com/remind101/stacker_blueprints/blob/master/stacker_blueprints/vpc.py) to `blueprints/vpc.py`
2. Copy Remind's [config.py](https://github.com/remind101/stacker_blueprints/blob/master/conf/example.yaml) to `config/config.yaml`

To achieve my reference VPC I'll need 3 environments: Management, NonProd, and Prod. Stacker has support for environments, so this starts with simply `touch config/environments/{management.env,nonprod.env,prod.env}`. Perfect!

Time for some customizations, starting with config.

### Configuring Stacker
The config from `example.yaml` is a great place to start but I needed some edits.

I have this custom `blueprints/` location for my stacks so I need to let Stacker know about that. I added

{% highlight bash %}
sys_path: .
{% endhighlight %}

to the top of `config.yaml`. This means I can only execute `stacker` commands from that `stacker/` directory I created above, a limitation that I'm fine with.

I also wanted to customize the S3 bucket where the templates are uploaded. I added

{% highlight bash %}
stacker_bucket: my-bucket
{% endhighlight %}

 after `sys_path` in `config.yaml`.

Finally time to customize the CF stacks that Stacker will manage. Without getting to deep in the woods, I ended up with a VPC stack that looks like this:

{% highlight yaml %}
- name: vpc
  class_path: blueprints.vpc.VPC
  # Flag to enable/disable a stack. Default is true
  enabled: true
  parameters:
    InstanceType: m3.medium
    SshKeyName: ${SshKeyName}
    ImageName: NAT
    # Only build 2 AZs, can be overridden with -p on the command line
    AZCount: 3
    PublicSubnets: ${PublicSubnets}
    PrivateSubnets: ${PrivateSubnets}
    DataSubnets: ${DataSubnets}
    CidrBlock: ${CidrBlock}
    # This zone will be added to the dns search path of the DHCP Options
    InternalDomain: ${InternalDomain}
    UseNatGateway: true
{% endhighlight %}

This differs from the example config in a few important ways:

* Stacker will look for the VPC class in `blueprints/vpc.py` (the `class_path` setting)
* I've set several of the parameters (`${SshKeyName}`, `${PublicSubnets}`, `${PrivateSubnets}`, etc) to be variables that are read from environment files. This let's me customize on a per-environment basis.

Setting up the environments takes no time at all. Each environment (not yaml, but it looks like it) file looks like this:

{% highlight yaml %}
namespace: management
SshKeyName: management-key
CidrBlock: 172.20.0.0/16
PublicSubnets: 172.20.0.0/24, 172.20.1.0/24, 172.20.2.0/24
PrivateSubnets: 172.20.10.0/24, 172.20.11.0/24, 172.20.12.0/24
DataSubnets: 172.20.20.0/24, 172.20.21.0/24, 172.20.22.0/24
InternalDomain: mydomain.com
{% endhighlight %}

The `namespace` sets up a naming convention to disambiguate stacks. Set up one namespace for each environment and customize accordingly.

### Customizing the VPC blueprint
Stacker blueprints are python code using the excellent [troposphere](https://github.com/cloudtools/troposphere) library which I've used quite a lot in the past. I had to make a few minor edits to the default VPC class for my needs. I won't go in to all the detail about those edits because customizing the blueprints is straightforward if you understand troposphere. If you don't, go learn it, you'll never go back to manually editing templates.

I did need to drop in to the support Slack room to ask a quick question. The default VPC blueprint does not name the resources, and I wanted to names so that things are identifiable in the AWS console. For example, the management VPC needed the `Name: management` tag. [@phobologic](https://twitter.com/phobologic) (Mike Barrett) was super helpful and gave me the answer right away. To refer to a namespace from within the blueprint, use `self.context.get_fqn(self.name)`. I modified the resource tags to include namespaces in the names like this:

{% highlight python %}
vpc_name_tag = self.context.get_fqn(self.name)
t.add_resource(ec2.VPC(
    VPC_NAME,
    CidrBlock=Ref("CidrBlock"),
    EnableDnsSupport=True,
    EnableDnsHostnames=True,
    Tags=Tags(Name=vpc_name_tag)))
{% endhighlight %}

### Building the stack
The fun part arrives: running the tool. Stacker makes it really easy to launch stacks with support for diff'ing the current state of a stack with the new state, tailing the cloudformation logs as the stack is being updated/created, and, my personal favorite, [change sets](https://aws.amazon.com/blogs/aws/new-change-sets-for-aws-cloudformation/). I used this command to create the management stack:

{% highlight bash %}
$ stacker build -r us-west-2 --stacks vpc -v -t config/environments/management.yml config/config.yml
{% endhighlight %}

Worked on the first try.

### Summing it up
Stacker is a huge improvement over working with raw CloudFormation. I'm working with a new client to build an ECS-based infrastructure, and I'm pretty excited to implement it all without typing any JSON and a minimal amount of YAML. I intend to integrate the Stacker workflowy in a Jenkins pipeline just as we do for the application code. The Stacker team is preparing the 1.0 release which will come with a bunch of improvements and fixes. Can't wait to see what they build next.
