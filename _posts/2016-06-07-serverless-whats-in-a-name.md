---
layout: post
title: "Serverless: what's in a name?"
excerpt: "The *serverless* moniker is rubbing a lot of people the wrong way. A cursory search for #serverless captures the prevailing sentiment:"
modified: 2016-06-07
comments: true
tags: [aws, serverless, lambda]
---

The "serverless" moniker is rubbing a lot of people the wrong way. A cursory search for #serverless captures the prevailing sentiment:

@fk_AndyJassy keeping it classy:
<figure class="whole">
<img src="http://i.imgur.com/FOtHuYI.png">
</figure>

The mockery is real:
<figure class="whole">
<img src="http://i.imgur.com/1oHbbpw.png">
</figure>

<figure class="whole">
<img src="http://i.imgur.com/7vIz91e.png">
</figure>

The fear is real:
<figure class="whole">
<img src="http://i.imgur.com/EbVda2L.png">
</figure>

The cluelessness is real:
<figure class="whole">
<img src="http://i.imgur.com/V1ZzS15.png">
</figure>

And of course the hype is real:
<figure class="whole">
<img src="http://i.imgur.com/qWaoJov.png">
</figure>

Recent posts from [acloud.guru](https://read.acloud.guru/debunking-serverless-myths-cc329460d061#.nr3y6g2ef) and [@PaulDJohnston](https://medium.com/@PaulDJohnston/serverless-is-just-a-name-we-could-have-called-it-jeff-1958dd4c63d7) try to bring some reason to the discussion. The former points out that yes, everybody understands there are actually servers still executing things, and that serverless is about shifting the overhead of server management to a service provider. The latter believes that the anti-serverless sentiment has a lot to do with fear and insecurity.

There are good points made in both of these articles, but neither really captures the problem that I have, which is not so much the word "serverless" as the prevailing attitude in the community. That somehow cloud functions will completely replace servers, and that if you're not using cloud functions you're doing it wrong. Gimmicks like physically destroying servers on stage at conferences aren't exactly helping. (On the other hand, I can appreciate it because as a long time sys admin, sometimes I really, *really* want to beat servers to a pulp!)

But that's not the only thing. *serverless* also sets the wrong expectations. It suggests that "server concerns" such as resource contention, OS settings (e.g. tunable kernel values), and runtime environment configuration (e.g. jvm settings) are irrelevant. Do developers write code just as they always have, only now they don't worry about how it runs? Of course not, but that's what serverless suggests.

Any informed developer will immediately understand that yes, there's still an OS, and you'd better still understand how it abstracts the underlying physical resources. Still, with serverless, you have basically no control over the execution environment, and you're restricted by the [limits set by the provider](http://docs.aws.amazon.com/lambda/latest/dg/limits.html). Don't like how something is configured? Too bad, you're stuck with it. Developers who use serverless exclusively live in a much smaller box and with a lot less freedom of expression than those with an open source OS at their disposal. [Serverless: Nice Idea, Terrible Name](http://blog.doismellburning.co.uk/serverless-nice-idea-terrible-name/) from Kristian Glass expresses some of these same concerns.

A whole host of server-related challenges go away completely with serverless, many in the domain of sys admins (now DevOps - another unfortunate name). Hardening the OS, patching, maintaining uniformity across environments, software packaging and deployments - these are just a few examples. All become much easier, at least in theory. But new responsibilities arise:

* Maintain granular permission for all your functions. And you thought managing IAM roles for your EC2 instances was hard...
* Resolve dependencies between hundreds or thousands of nanoservices
* Maintain and publish versions of various functions
* Mock the execution environment to make sure local development closely matches the provider's environment
* Ensure that the code obeys the aforementioned environmental restrictions

Most (all?) of this is now squarely in the domain of the developer. Tooling will help to address it (the most obvious current example being the well regarded Serverless framework), and I anticipate a healthy ecosystem of complementary and competing tools that make this easier over time. But we need to acknowledge that some of the same challenges have shifted in to new areas.

Should you be worried about your future career if you're a sys admin/DevOps/SRE? Absolutely not. Think of serverless as another tool in the box. Cloud functions have joined the ranks of PaaS, containers, cloud instances, private VMs, and bare metal servers in running code to solve business problems. They're extremely efficient and sensible in the right situation, and we should expect them to gain new features and improve over time. But servers aren't going away any time soon, and today's legacy applications and development patterns will be here for many years to come. If you're afraid of the change that serverless brings, well, you're in the wrong industry my friend.

Love it, hate it, get used to it. Cloud functions are here to stay, and serverless is too.