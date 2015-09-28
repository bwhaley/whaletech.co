---
layout: post
title: "Extending boto3"
excerpt: "Using the event system to add an attribute to boto3 SecurityGroup objects, making it easier to interact with rules."
modified: 2015-09-25
comments: true
tags: [aws, boto3, python]
---
[boto](https://github.com/boto/boto), the esteemed Python SDK for the AWS API, is being retired in favor of [boto3](https://github.com/boto/boto3), which has been deemed "stable and recommended for general use." There are at least two big enhancements in boto3:

1. Interfaces to AWS are driven automatically by [JSON service descriptions](https://github.com/boto/botocore/tree/develop/botocore/data) rather than hand-coded. As a result, the features provided by the SDK are both more current and more portable since SDKs in many languages can use the same JSON descriptions.
2. *Resources*, *collections* and related high-level interfaces offer a more pythonic and object-oriented experience for interacting with AWS.

In August, AWS released the [Extensibility Guide](http://boto3.readthedocs.org/en/latest/guide/events.html) for boto3. Quoting the guide:

> All of Boto3's resource and client classes are generated at runtime. This means that you cannot directly inherit and then extend the functionality of these classes because they do not exist until the program actually starts running. However it is still possible to extend the functionality of classes through Boto3's event system.

The documentation goes on to give some trivial examples, but it still wasn't immediately obvious to me, a relative Python neophyte, how to use this in my own development. I recently had a project where the ability to extend boto3 would simplify my code, and I'd like to share what I did.

## Problem Statement
Many of my clients have complex applications with several AWS VPCs, external networks, and a lot of moving parts with many teams managing the various systems. I am often hired to help with the design and the security of these environments, and in that role I end up doing a lot of vulnerability assessment work.

Assessments require a lot of data collection about the network architecture, security group structure, permissions, and other settings in the environment. Previously I spent a lot of time clicking through the console and making notes, a tedious process that was both time consuming and error prone.

I set about coding up a tool to collect as much of the data as possible automatically, and also to draw some conclusions about the security of the system based on the data. I learned how simple it is to extend boto3 using the event system.

## An Example: Security Group Rules
The `ec2.SecurityGroup` class in boto3 contain an `IpPermissions` attribute that represents the group's inbound rules. The attribute is a list of rules in JSON format, looking something like this:

    IpPermissions=[
        {
            'IpProtocol': 'string',
            'FromPort': 123,
            'ToPort': 123,
            'UserIdGroupPairs': [
                {
                    'UserId': 'string',
                    'GroupName': 'string',
                    'GroupId': 'string'
                },
            ],
            'IpRanges': [
                {
                    'CidrIp': 'string'
                },
            ],
            'PrefixListIds': [
                {
                    'PrefixListId': 'string'
                },
            ]
        }
    ]


I wanted to analyze the rules, and converting this JSON blob to a proper Python object would allow me to work with individual rules more easily.

To do this, I extend boto3 with two classes: `SecurityGroupRules`, used to add an attribute called `rules` to `SecurityGroup`, and then `SecurityGroupRule` (note singular vs plural) to represent a single rule. The `rules` attribute can be created when the object is initialized. Something like this:

{% highlight python linenos %}
class SecurityGroupRules(object):
    def __init__(self, *args, **kwargs):
        """Adds the attribute `rules` to SecurityGroup. `rules` is a list of
        SecurityGroupRule objects.
        """
        super(SecurityGroupRules, self).__init__(*args, **kwargs)
        self.rules = self.ip_permissions

    @property
    def rules(self):
        return self._rules

    @rules.setter
    def rules(self, ip_permissions):
        if type(ip_permissions) is not list:
            raise TypeError("Expected list, found %s" % type(ip_permissions))
        self._rules = []
        for rule in ip_permissions:
            protocol = rule.get('IpProtocol')
            from_port = rule.get('FromPort')
            to_port = rule.get('ToPort')
            source_groups = []
            for source_group in rule.get('UserIdGroupPairs'):
                source_groups.append(SourceGroup(user_id=source_group.get('UserId'),
                                                 group_name=source_group.get('GroupName'),
                                                 group_id=source_group.get('GroupId')))
            cidr_ranges = []
            for ip_range in rule.get('IpRanges'):
                cidr_ranges.append(ip_range['CidrIp'])
            prefix_lists = []
            for pfx in rule.get('PrefixListIds'):
                prefix_lists.append(pfx['PrefixListId'])
            self._rules.append(SecurityGroupRule(protocol=protocol,
                                                 from_port=from_port,
                                                 to_port=to_port,
                                                 source_groups=source_groups,
                                                 cidr_ranges=cidr_ranges,
                                                 prefix_lists=prefix_lists))
{% endhighlight %}


The setter method extracts the fields from the `ip_permissions` JSON blob and creates a `SecurityGroupRule` object for every rule.

`SecurityGroupRule` looks like:

{% highlight python linenos %}
from collections import namedtuple
SourceGroup = namedtuple('SourceGroup', 'user_id group_name group_id')
CidrRange = namedtuple('CidrRange', 'cidr')
PrefixList = namedtuple('PrefixList', 'prefix_list')
PROTOCOLS = [
    '-1',
    'tcp',
    'udp',
    'icmp'
]

class SecurityGroupRule(object):
    def __init__(self, protocol, from_port=None, to_port=None, source_groups=None, cidr_ranges=None, prefix_lists=None):
        """See also http://boto3.readthedocs.org/en/latest/reference/services/ec2.html#securitygroup
        """
        self.protocol = protocol
        self.from_port = from_port
        self.source_groups = source_groups
        self.cidr_ranges = cidr_ranges
        self.prefix_lists = prefix_lists
        self.snoop_findings = None

    @property
    def protocol(self):
        return self._protocol

    @protocol.setter
    def protocol(self, value):
        if value not in PROTOCOLS:
            raise TypeError('Encountered an unknown protocol %s' % value)
        self._protocol = value

    @property
    def from_port(self):
        return self._from_port

    @from_port.setter
    def from_port(self, value=None):
        if not value or port_is_valid(value):
            self._from_port = value
        else:
            raise TypeError('Encountered an unknown port %s' % value)
    @property
    def to_port(self):
        return self._to_port

    @to_port.setter
    def to_port(self, value=None):
        if not value or port_is_valid(value):
            self._to_port = value
        else:
            raise TypeError('Encountered an unknown port %s' % value)

    @property
    def source_groups(self):
        return self._source_groups

    @source_groups.setter
    def source_groups(self, values):
        """List of SourceGroup() named tuples
        """
        if values:
            for v in values:
                if not isinstance(v, SourceGroup):
                    raise TypeError('Expect a list of source groups but found %s' % v)
        self._source_groups = values

    @property
    def cidr_ranges(self):
        return self._cidr_ranges

    @cidr_ranges.setter
    def cidr_ranges(self, values):
        """List of CidrRange() named tuples
        """
        valid_cidr = "^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\/([0-9]|[1-2][0-9]|3[0-2]))$"
        if values:
            for v in values:
                if not re.match(valid_cidr, v):
                    raise TypeError('Expect a valid CIDR IP range but found %s' % v)
        self._cidr_ranges = values

    @property
    def prefix_lists(self):
        return self._prefix_lists

    @prefix_lists.setter
    def prefix_lists(self, values):
        """List of PrefixList() named tuples
        """
        if values:
            for v in values:
                if not isinstance(v, PrefixList):
                    raise TypeError('Expect a list of PrefixList() but found %s' % str(v))
        self._prefix_lists = values

def port_is_valid(port):
    return isinstance(port, int) and (port == -1 or 1 <= port <= 65535)

{% endhighlight %}

Great, so how do we use these classes? Enter the event system magic: register the `SecurityGroupRules` class to be added when boto3 instantiates a `SecurityGroup`.

{% highlight python linenos %}
def get_ec2_handle():
    session = Session()
    session.events.register('creating-resource-class.ec2.SecurityGroup', add_custom_sg_class)
    return session.resource('ec2')

def add_custom_sg_class(base_classes, **kwargs):
    base_classes.insert(0, SecurityGroupRules)
{% endhighlight %}

Whenever a SecurityGroup object is created using the handle returned from `get_ec2_handle()`, SecurityGroupRules will also be instantiated. As a trivial example:

{% highlight python linenos %}
ec2_handle = get_ec2_handle()

# Get all the instances in an account
# Use list() to force boto3 to make calls to AWS now
# May take a some time if there are many instances!
instances = list(ec2_handle.instances.all())

# Get a unique list of security groups from all in-scope instances
all_groups = []
for i in instances:
    for sg_id in i.security_group_ids:
        all_groups.append(sg_id)

all_groups = set(all_groups)

security_groups = []
for sg_id in all_groups:
    security_groups.append(ec2_handle.SecurityGroup(sg_id))
{% endhighlight %}

`security_groups` is a list of `SecurityGroup` objects, each of which has a `rules` attribute that is a list of `SecurityGroupRule` objects. It's now trivial to list all rules in all groups:

{% highlight python linenos %}
for sg in security_groups:
  for rule in sg.rules:
    print rule.protocol
{% endhighlight %}


We can also easily search the rules for insecure configurations, which is more detail than I planned for this post. So what's considered an insecure configuration? Well that's also not really the point of the post, but since you've asked my opinion...

* All ports to the zero network (0.0.0.0/0) (obvious)
* Any ports to the zero network should at least be noted
* Access to all or many ports for a large CIDR range, where large is my somewhat arbitrary definition - `/24` or larger.

The idea is that even internal to a VPC, security groups should be as restrictive as possible.

## Wrapping Up
The boto3 event system is a novel approach to allow more pythonic interactions with AWS resources. This example showed how to essentially subclass `ec2.SecurityGroup` to allow better analysis of rules. I also subclass `ec2.Instance` to extract additional instance properties which aren't immediately available, like IAM policies and instance userdata.

Please hassle me in the comments or [on teh Twitter](https://twitter.com/iAmTheWhaley) about how bad my Python code is or to correct/clarify anything. Thanks for reading.
