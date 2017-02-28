---
layout: post
title: "Ansible playbook for additional CA Certs"
excerpt: |
  I recently needed to add an additional Comodo cert to Ubuntu 14.04 instances. I put the following plays in my <code>common</code> Ansible role that is applied to all my systems:
modified: 2014-07-23
comments: true
tags: [ansible]
---
I recently needed to add an additional Comodo (lol)cert to Ubuntu 14.04 instances. I put the following plays in my `common` Ansible role that is applied to all my systems.

{% highlight yaml %}
- name: Ensure local certs directory exists
  file: state=directory path=/usr/local/share/ca-certificates

- name: Install comodo cert
  copy: src=COMODORSAddTrustCA.crt dest=/usr/local/share/ca-certificates/COMODORSAddTrustCA.crt

- name: Update cert index
  shell: /usr/sbin/update-ca-certificates
{% endhighlight %}

This is the "right" way to add local CA certs, codified.
