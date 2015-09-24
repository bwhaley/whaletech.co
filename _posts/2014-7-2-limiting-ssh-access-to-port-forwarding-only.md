---
layout: post
title: "Limiting SSH access to port forwarding only"
excerpt: "<p>It's nothing new or novel but I don't recall this sort of minutiae off the top of my head. </p>
<p>Recently I needed to limit SSH access for a service account (jenkins) to only be able to tunnel to a specific port on a specific host. I was able to do this using <code>.ssh/authorized_keys</code> f..."
modified: 2014-7-2
comments: true
tags: [security, ssh]
---
It's nothing new or novel but I don't recall this sort of minutiae off the top of my head.

Recently I needed to limit SSH access for a service account (jenkins) to only be able to tunnel to a specific port on a specific host. I was able to do this using `.ssh/authorized_keys` file wizardry. Behold:

{% highlight bash %}
command="echo 'This account can only be used for database access'",no-agent-forwarding,no-X11-forwarding,permitopen="<mysqlhost>:3306" ssh-rsa AAAAB...[snip]
{% endhighlight %}

All the details are in the ridiculously complete [sshd man page](http://www.openbsd.org/cgi-bin/man.cgi?query=sshd&sektion=8).
