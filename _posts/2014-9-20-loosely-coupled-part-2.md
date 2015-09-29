---
layout: post
title: "Loosely Coupled, Part Two"
excerpt: |
  <p>This post continues my thoughts on loosely coupled infrastructure. If you haven't read <a href="https://www.whaletech.co/2014/09/20/loosely-coupled-part-2.html">part 1</a>, this would be a good time to do so.</p>
  <h2>S3</h2>
  <p>In his 2012 re:Invent keynote, Werner Vogels outlines several architectural tenants for build...
modified: 2014-9-20
comments: true
tags: [theory]
---


This post continues my thoughts on loosely coupled infrastructure. If you haven't read [part 1](https://www.whaletech.co/2014/09/20/loosely-coupled-part-2.html), this would be a good time to do so.

##S3
In his 2012 re:Invent keynote, Werner Vogels outlines several architectural tenants for building on AWS. One of them succinctly states,

> Decompose into small, loosely coupled, stateless building blocks

The [example he uses (video link)](https://www.youtube.com/watch?v=PW1lhU8n5So#t=1208) is around the crushing traffic that Amazon.com would send to IMDB when a new blockbuster movie went on sale and the pages were served straight from IMDB's system. There was little or no coordination between the Amazon and IMDB teams, and subsequently the service would chug along slowly or fail entirely.

To solve the problem, the engineers designed a solution in which IMDB movie info was pushed as static assets to an S3 bucket, and Amazon.com would look for the data there, thus circumventing that dependent relationship.

<figure>
<a href="https://i.imgur.com/FGJA0s7.png"><img src="https://i.imgur.com/FGJA0s7.png"></a>
</figure>

I've used this pattern myself to separate query jobs from a reporting interface. Several query jobs run on several databases that are spread among multiple VPCs. The databases vary both in instance type and in volume of data, and the query time is highly variable. When the query job completes, it sends results to an S3 bucket. A worker on the reporting side polls the bucket for new data, and when data is found the worker consumes, processes, and stores it in another database for reporting.

<figure>
<a href="https://i.imgur.com/Ii1DnrU.png"><img src="https://i.imgur.com/Ii1DnrU.png"></a>
</figure>

Using this design, every piece of the system becomes modular. So long as the producers conform to the message format, the consumer can read the updates periodically for ingest to the reporting system. More producers can be added, or the consumer worker can be removed from the system for a time with no adverse outcomes.

An especially nice side effect of this approach is the granular permissions that are possible when using S3 with IAM. The producers have write only access, while the reader can only list, get, and delete objects. We also achieve network separation by running the services in distinct VPCs, though of course it is not required.

##Proxies
Most services running in the cloud are proxied behind a load balancer, decoupling clients from the web servers to assist with handling load and assuring that the service is available on a given instance via health checks. Proxies turn out to be useful for decoupling at other tiers as well. For example, one common use case is to use HAProxy in front of [multi-master MySQL](https://www.digitalocean.com/community/tutorials/how-to-set-up-mysql-master-master-replication), allowing for load balancing of the database.

<figure>
<a href="https://i.imgur.com/NDr3zLM.png"><img src="https://i.imgur.com/NDr3zLM.png"></a>
</figure>

In this example, HAProxy lives on each instance, perhaps running in a container, and is configured with each of the downstream master MySQL databases. HAProxy can even run health checks against the database servers, removing one from service if a problem arises.  Unfortunately this particular approach is not offered as a service on AWS, nor is multi-master MySQL replication.

A proxy can actually be used for decoupling any time there's 1) a dependent downstream service, and 2) the resources providing that service are accessible at multiple endpoints simultaneously.

##Asynchronous Operations
Services that communicate in a synchronous fashion are implicitly tightly coupled. This is often unavoidable: an HTTP user request/response, or an ACID-compliant relational database transaction, must be synchronous. But other functionality can communicate asynchronously to avoid tight coupling.

An API request to a dependent backend service, for example, can be handled in the background in a non-blocking manner. Consider the case of an application that accepts incoming search requests and wishes to track the popularity of certain keyword terms. The service might use the [3scale sentiment API](https://github.com/3scale/sentiment-api-example) for tracking the sentiment of a given term, but it doesn't make sense to wait for that API to return before processing the search query.

This could be solved using Nginx and Lua in front of the application. Lua could parse the search term from the query and submit the term to the sentiment API without blocking the request processing.

{% highlight lua %}
require("os")
local cjson = require "cjson"
local m = ngx.re.match(ngx.var.request, "/api/search/(.*) ")
if m then
  local word = m[1]
  local res = ngx.location.capture("/v1/word/" .. word .. ".json")
  local value = cjson.new().decode(res.body)
  if value.sentiment < 5 then
    local new_sentiment = value.sentiment + 1
    local res = ngx.location.capture("/v1/word/" .. word .. ".json?value=" .. new_sentiment, { method = ngx.HTTP_POST })
  end
else
  return
end
{% endhighlight %}

This Lua snippet will search the request path for `/api/search/<word>`, then submit the `word` to another endpoint, `/v1/word/<word>.json`, which submits the request (asynchronously) to 3scale. If the sentiment is less than 5, the sentiment is increased by one. The search request may have already completed and returned a response to the user. The Lua is executed directly within the Nginx configuration, and the logic never touches the application code.

##Service Discovery
As it happens, configuration is one of the hardest things about software delivery, precisely because the configuration is tightly coupled to the application logic. When resources change, for example because new systems become available, the URI of an existing service changes, or a system becomes unhealthy, the configuration must also change for the application to continue. The service may require a restart to reload new configuration.

In a typical deployment of Puppet, Chef, Ansible, Salt, etc configuration is codified but static, residing alongside the CM DSL in version control. When a value changes, for example a new resource URI is needed, the CM tool must run again to update the runtime config. It may run periodically, or may be kicked by some remote process so that it starts immediately. The tool will notify any services that need to be restarted, and may even orchestrate the restart across multiple hosts.

Service discovery automates the configuration process, decoupling the data from the config management. The systems are usually distributed and fault tolerant, and may offer health checking. Clients use an interface to discover configuration data, and services register and deregister themselves as they come online and offline.

Implementations vary. In [HashiCorp's Consul](http://www.consul.io/intro/index.html), the query interface is HTTP or DNS, and sits atop [Serf](http://www.serfdom.io/) for clustering. [Flynn's](http://flynn.io) [discoverd](https://github.com/flynn/flynn/tree/master/discoverd) system abstracts the backing service discovery system (current backends are [etcd](https://github.com/coreos/etcd), [zookeeper](http://zookeeper.apache.org/)) and even offers a configuration rendering system to allow for service discovery in software that doesn't support it (that is to say, most software). I recently attended a talk by Igor Serebryany of Airbnb who [built and open sourced SmartStack](http://nerds.airbnb.com/smartstack-service-discovery-cloud/), an alternative approach that relies on Zookeeper for configuration data, and wraps around HAProxy as an interface between applications and their resources.

Using service discovery, applications no longer require static configuration. Changes in configuration can be communicated to software in a highly reliable, [mostly consistent](http://aphyr.com/posts/316-call-me-maybe-etcd-and-consul), low latency fashion. Service discovery then loosens the coupling between a software and its configuration.

##Wrapping Up
These examples of loose coupling demonstrate that reducing direct dependencies between applications and their backing resources can improve both the flexibility and the availability of the service. Thanks to AWS, achieving a loosely coupled design may involve only a few API calls. It can even be worthwhile to refactor existing software to interact through queues or S3 buckets in order to benefit from the flexibility of loosely coupled components.

Have more examples to share? Want to tell me I'm wrong about something? Let me know on Twitter @iAmTheWhaley.
