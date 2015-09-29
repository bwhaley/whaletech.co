---
layout: post
title: "AWS re:Invent 2014: Initial Reactions to EC2 Container Service and Lambda"
excerpt: |
  Another re:Invent in the bag! I'm beginning to digest the new services and trends I saw after listening to the keynotes, walking the exhibition hall floor, and chatting with what feels like all 13,000 people that attended. Here are my immediate impressions of the two most-hyped services since that's all I have time for now.
modified: 2014-11-14
comments: true
tags: [containers, ecs, reinvent, aws]
---
<br/>
<figure>
<a href="https://i.imgur.com/wKrYxQb.png"><img src="https://i.imgur.com/wKrYxQb.png"></a>
</figure>

Another re:Invent in the bag! I'm beginning to digest the new services and trends I saw after listening to the keynotes, walking the exhibition hall floor, and chatting with what feels like all 13,000 people that attended. Here are my immediate impressions of the two most-hyped services since that's all I have time for now.

##[EC2 Container Service](https://aws.amazon.com/ecs/)

<figure>
<a href="https://i.imgur.com/PDj3uc4.png"><img src="https://i.imgur.com/PDj3uc4.png"></a>
</figure>
You might have heard about this thing called Docker that's been going around. As expected, Amazon's container service is built around Docker and the Docker Hub and promises a nice cluster abstraction to running containers on a fleet of EC2 instances. It even comes complete with an awesome spaceport for moving containers around! Docker CEO Ben Goleb went to bat on stage with Werner pronouncing a deep integration and partnership with Amazon.

First impressions are challenging here since the service basically isn't ready yet. It's available as a preview only, and previews aren't being given lightly. My impression is that the AMIs aren't available, there isn't yet integration with other services like ELB, and customizations are basic at best. Barb Darrow over at Gigaom is [predictably underwhelmed](https://gigaom.com/2014/11/14/top-5-lessons-learned-at-aws-reinvent/) by the new service offering, calling it "no Kubernetes".

Still, AWS has a track record of releasing an MVP and iterating quickly. The dream is to have a generic, homogeneous fleet of compute capacity to which containers can be deployed transparently. The container service manages resources, distribution of containers, scheduling, and more. The other tools in this space are greenfield, at least as far as best practices are concerned.

I've been running Docker in production settings since (stupidly) version 0.5. The product is fantastic and the benefits are real, but it's clear that a service like this is needed to simplify the orchestration and configuration. I'm excited to see this service improve rapidly.

##[Lambda](https://aws.amazon.com/lambda/)
Also available in preview only is Lambda, "a compute service that runs your code in response to events and automatically manages the compute resources." When an event occurs, like a new object uploaded to an S3 bucket or an message arrives on a Kinesis stream, a "trigger" calls a cloud function to process the event. Cloud functions are written in Node.js and can be daisy chained to create more complex interactions. Rumors abound that additional languages may be launched soon. Lambda functions can even be triggered on a scheduled basis, which I'll use to replace some cron jobs.

People that I spoke to at the conference were very impressed with this announcement. I tweeted that it replaces an entire tier of worker instances that do nothing but process streams of event data. No longer are full blown EC2 instances needed for simple message processing. Mitch Garnaat (whom I didn't have the pleasure of meeting, sadly) tweeted:

> A double leapfrog maneuver. Containers leapfrog virtualization and then Lambda leapfrogs containers. Well played.

This is perhaps the most innovative service from AWS since the release of EC2 and S3. It dramatically simplifies running code in the cloud, lowering the bar to running services even more than PaaS tools. Consider the possibilities if an ELB trigger was released so that a Lambda function could handle HTTP/S.

It's not a complete application replacement, of course. Some complex systems cannot be easily modeled as purely event driven functions. And I expect some lessons will be learned the hard way when developers don't consider the implications of Lambda functions causing a recursive chain of events. Imagine that an image arrives in a bucket, triggering a Lambda function to process that image and puts it back in the bucket. If the function uploads the image to the same bucket, another function might be triggered to process the already-processed image, for an inception of image processing that costs the developer for each call. AWS warned against during the session discussing Lambda.

People who have signed up for the preview are already getting access. I can't wait to see what clever things people will build on Lambda.

## Coming up next
This is just a brief treatment of two of the nine services launched at re:Invent. The other big hitters were the Aurora RDS, the CodeDeploy/Commit/Pipeline services, and the Key Management Service. I'll blog about those in an upcoming post.

Amazon is clearly pushing the industry it founded forward with innovative, high impact services that are exactly what customers asked for. Now let's get to work and build something interesting.
