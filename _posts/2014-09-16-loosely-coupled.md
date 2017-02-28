---
layout: post
title: "Loosely Coupled"
excerpt: |
  <p>Much ado has been made recently regarding service oriented architectures and microservices. Martin Fowler <a href="http://martinfowler.com/articles/microservices.html">wrote</a> a long article about what Microservices means from a 40,000 foot view...
modified: 2014-09-16
comments: true
tags: [theory]
---
Much ado has been made recently regarding service oriented architectures and microservices. Martin Fowler [wrote](http://martinfowler.com/articles/microservices.html) a long article about what Microservices means from a 40,000 foot view. In [an interesting podcast](https://s3.amazonaws.com/SystemsLive/Episode42.mp3), Timothy Fritz and Jeff Lindsay discuss the merits and demerits of SOA and microservices, ultimately concluding that they introduce more complexity (via language and repository sprawl) than is warranted by the benefits. Another [tongue-in-cheek article](http://www.chrisstucchio.com/blog/2014/microservices_for_the_grumpy_neckbeard.html) arbitrarily defines a microservice as comprising fewer than 5,000 lines of code and at most five endpoints.

For the uninitiated, Martin Fowler's article linked above describes microservices as the following:

>The microservice architectural style is an approach to developing a single application as a suite of small services, each running in its own process and communicating with lightweight mechanisms, often an HTTP resource API. These services are built around business capabilities and independently deployable by fully automated deployment machinery.

Much more experienced (and opinionated) people than myself have a lot to say about microservices, yet none can agree on a definition, so I won't attempt to define it here. It's not at all clear whether SOA and microservices are actually the same thing or not. I really can't see any differences, except that SOA has been around for a while and microservice is a nice buzzword.

Defining loose coupling, on the other hand, is more straightforward: a design in which two or more related components are implemented with minimal interdependencies. As a design pattern, loose coupling is at the core of any SOA/microservices architecture. Loose coupling reduces complexity. Fewer dependencies among systems leads to improved flexibility, ultimately trending towards a cohesive, sensible set of independent services that embody the UNIX tradition of *do one thing and do it well*.

There are many examples of loose coupling in software development (start with [the Wikipedia article](https://en.wikipedia.org/wiki/Loose_coupling) and work your way out), but I've found far fewer examples of loose coupling as applied to systems architecture.

In this series of two posts I'll present examples of loose coupling focused on infrastructure, and in particular on Amazon Web Services, where I spend most of my time these days. The intent is to demonstrate how loosely coupled infrastructure design leads to more manageable, robust, and scalable compute environments.

## Queues
We'll begin with the obvious: message queues, a classic example of decoupling. A message queue is the epitome of simple decoupling. Bob Nystrom describes it pragmatically in his [article on event queues](http://gameprogrammingpatterns.com/event-queue.html):

> I think of it in terms of pushing and pulling. You have some code A that wants another chunk B to do some work. The natural way for A to initiate that is by pushing the request to B.

> Meanwhile, the natural way for B to process that request is by pulling it in at a convenient time in its run cycle. When you have a push model on one end and a pull model on the other, you need a buffer between them. That’s what a queue provides that simpler decoupling patterns don’t.

> Queues give control to the code that pulls from it — the receiver can delay processing, aggregate requests, or discard them entirely. But queues do this by taking control away from the sender. All the sender can do is throw a request on the queue and hope for the best. This makes queues a poor fit when the sender needs a response.

Bob's description is meant for event handling within a game, but the premise applies just as naturally to web workers. If a client doesn't require an immediate response, for example in the case of background workers, cleanup tasks, or event streams (maybe analytics data) that don't require immediate handling, a queue may be a good fit.

Here's an example: A user account system exposes an API for account creation and management. The accounts are required to be verified by email.  The initial account creation process should trigger the email immediately; the user shouldn't have to wait long in order to verify his or her account.

But there are housekeeping tasks that must be tended to. After a day or two it might make sense to follow up with a reminder to verify for accounts that never did, and after a few more days those unverified accounts should be purged from the system altogether.

The business may also derive value from user account access. A log in, account update, account delete, or certain other activities may be of interest for business analytics. These need not be processed in real time, but they also shouldn't be lost.

These could be situations where a queue is used to decouple maintenance or analytics workers from the primary application, whose responsibility it is to service account management. In the case of the analytics pipeline, the queue may be used to completely separate services.

In AWS,  "the Simple Queue Service (SQS) is a fast, reliable, scalable, fully managed message queuing service" that "makes it simple and cost-effective to decouple the components of a cloud application." Interaction with SQS is entirely via https. Permissions can be granted explicitly via the queue settings as well as via AWS IAM. Messages can be up to 256Kb in size and will remain on the queue for up to 14 days.

<figure>
<a href="https://i.imgur.com/pw1MM07.png"><img src="https://i.imgur.com/pw1MM07.png"></a>
</figure>

For applications already built on the AWS ecosystem, SQS is a solid contender for use as an application's messaging service. As a managed service, SQS adds basically no operational burden; it is truly set and forget. In my monitoring dashboards I include queue depth as well as sent, received, and deleted messages, which helps me to infer the status of producers and consumers.

Last year during Christmas I was glued to my monitoring dashboards. I was (and still am, part time) working at [Anki](https://anki.com), and we experienced our biggest usage day ever when DRIVE kits and expansion cars were opened and families around the country enjoyed time together with fast, killer robot cars. The volume of analytic data we consumed was an order of magnitude larger than ever before, but thanks to the queue this was no problem. The queue grew in size to more than 8,000,000 messages. Rather than worry about dropping messages and losing data, I was able to tune the database to ensure we could actually process the queue within the 14 day window.

Stay tuned for part two where I'll discuss more examples of loosely coupled infrastructure. If you have something to contribute, or if you think I'm wrong and I should know it, or if I can help you with a problem, let me know.
