---
layout: post
title: "The Fallacy of Cloud Lock In"
excerpt: |
  <p>"Let's design this to be agnostic in case we want to switch cloud vendors later."  -- Person focused on the wrong things</p>
modified: 2014-12-3
comments: true
tags: [cloud, opinion]
---
> "Let's design this to be agnostic in case we want to switch cloud vendors later."  -- Person focused on the wrong things

In a [recent post](https://www.whaletech.co/2014/12/03/the-fallacy-of-lock-in.html) I said, 'Some users will cry "lock-in" and avoid Aurora. Those users are missing the point of AWS.' Since then I've had a number of questions about what I meant by this so I thought I'd write a quick post on what I believe to be a widespread yet short-sighted belief: that tightly coupling with a cloud vendor is a Really Bad Idea. And yes, before you ask, I'm mainly focused on AWS, but the point applies more broadly.

At what point do you cross the line from "agnostic" to "locked in"? Using EC2 with ELB? Autoscaling and S3? IAM and the new Key Management Service? By choosing to run a service in the cloud, you naturally have to do at least some coupling with the chosen platform. Using EC2 for a web service? Unless you're running on a single instance exposed to the world, you're probably going to need a load balancer. So then you'll either design a solution yourself, a [reasonably difficult choice fraught with complexity](http://code.naishe.in/2012/11/high-availability-ngnix-using-heartbeat.html), or you'll take the easy route and choose to use an ELB. But wait! Now you're locked in!

But EC2 and ELB are probably not the line people are worried about. You could, after all, quite easily move your application to another vendor and use its load balancer product. The concern is likely about the more proprietary AWS products such as DynamoDB, OpsWorks, IAM. Building a product around DynamoDB's API, designing a deployment pipeline on OpsWorks, or tapping IAM for handling AWS keys is not easily portable to another vendor, no matter how you look at it. So those products should be avoided, right?

The perspective is posited on multiple mistaken beliefs: that the business may want to switch in the near future, the service is too costly, and the complexity too great. I take issue with each point

* Is it more important for the business to focus on building an agnostic product, or should it instead be using all the tools available on the platform it selected to build the best product that it can? Put in the work up front during the selection process, and then embrace that platform completely.
* The cost of the service should be considered holistically. Is Digital Ocean cheaper than EC2? Maybe on the surface, but many of the ancillary services on AWS (CloudFormation, OpsWorks and Elastic Beanstalk, IAM) are free, and have no equivalent elsewhere. This is a native benefit of choosing AWS as a platform, and one that will pay back as products scale with the success of the business.
* There is a relationship between the complexity of the platform and the flexibility it provides. Sure, choose a PaaS if you want a mostly hands off deployment process. But if you run on Heroku, you don't get a shell and your customization options are limited. Build on a Linode VM, but then build your own load balancers, distributed database servers, caching cluster, highly available queue, and by the way figure out how to manage accounts for the entire team. When choosing a vendor with an intimidating array of products, learn how to use them natively for best results.

It boils down to integration. AWS is an integrated and related suite of services offering flexiblity, customization, and in some cases unmatched innovation (looking at you, Lambda and IAM). Applications that are built leveraging these features will benefit from this integration, while those that don't will suffer from agnostic complexity.

I maintain my position: if you're worried about lock in, you're missing the point.
