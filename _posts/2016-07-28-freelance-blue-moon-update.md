---
layout: post
title: "Blue moon update"
excerpt: "Full time consulting life working at home turns out be, well, quite a lot of work! But finally I'll make time for a few thoughts and updates."
modified: 2016-07-28
comments: true
tags: [freelance, consulting, aws, mesos, moving]
---
Full time consulting life working at home turns out be, well, quite a lot of work! But finally I'll make time for a few thoughts and updates.

## Portland or bust
I'm relocating to Portland! Shocking, I know, to hear about somebody moving from NorCal to Portland. It's a beautiful city with remarkable neighborhoods and a vibrant tech scene, and of course great beer. I'm looking forward to meeting new people so if you're in the area lmk!

## Consulting
August 1st marks two packed years of consulting! Business is thriving with several notable changes in the past few months.

WhaleTech has added two consultants to the team: fellow AWS hero Larry Ogrodnek and Brandon Mumby, a highly capable cloud and Linux geek. It gives clients peace of mind knowing that I'm not the only one around, and I'm able to handle more projects. I'm enjoying having professionals on the team that I trust to do the right thing for clients.

From an "employer" perspective, WhaleTech values freedom and independence above all else. The other consultants on the team remain independent and can take on the amount of work that they choose on an hourly basis. WhaleTech works with seasoned cloud experts who have a proven track record of problem solving and delivering software. 

I've shifted focus from lots of new clients to an expanded scope at existing clients. It's easier and lower overhead to work a few projects within a larger business than to context switch constantly between completely different clients. There's risk in being overexposed to a single client, but having more consultants on the team will help with this.

## On Mesos
The past several months I've been migrating a large scale, production microservices system to Mesos. It has been really fun and interesting, and also a lot of work. A few of the highlights:

- Chef cookbooks for all the parts: mesos, marathon, consul, haproxy
- Bits and pieces of the excellent [Mantl](https://github.com/CiscoCloud/mantl) project from Cisco, in particular their implementation of consul-template for haproxy and their marathon-consul bridge
- Grafana + Graphite for dashboards, ELK stack for log ingestion. Filebeat and Logstash have been useful to parse out the container app logs from the mesos agents
- Consul used for K/V and also as DNS servers for the mesos cluster. Consul recurses to the standard VPC DNS server.
- HAProxy with SNI as a request router, with support for two-way SSL. 
- A Jenkins-based single click deploy system, using lambda functions as a gateway to remote clusters (e.g. clusters in other AWS accounts or in other non-peered networks). Maybe a future blog post on this.

I have found Mesos to be incredibly stable and reliable, though challenging to debug. Marathon is intuitive and the teams using it have had no problem coming up to speed. Consul has been equally stable and quite straightforward to work with.

That said, I used up a lot of glue piecing it all together. The list of "stuff" goes on and on: 

- How to get container logs out of docker and in to ELK? 
- What tools should you use to collect container metrics? host metrics? mesos metrics? 
- How to configure HAProxy for services that use two-way TLS?
- Don't forget to do TLS for Consul. And Docker. And mesos. And Marathon. And...
- Which Docker storage driver to use
- What servers to use as DNS resolvers in the containers
- etc etc

The point is, a custom-built container platform is a hairy beast indeed, and rickety at best. Consider how to update/reconfigure all the bits & pieces! Next time I'll take a closer look at DCOS, which at the time didn't seem to do much beyond this anyway glossed over a lot of details. For a large scale platform, especially in security sensitive environments, the all-in-one "cluster in a box" tools generally won't do the trick.

## What's next?
Work on ULSAH 5th edition continues. It's a long, slow slog, but we've been making steady progress. I have proof! This is a screenshot of my personal summary page showing the status of chapter reviews by peers and other authors:

<figure>
<a href="http://i.imgur.com/yr1GpAq.png"><img src="http://i.imgur.com/yr1GpAq.png"></a>
</figure>

There's a light at the end of that tunnel, but it's barely a glimmer.

Seriously, look me up if you're in Portland. Can't wait for the next adventure.
