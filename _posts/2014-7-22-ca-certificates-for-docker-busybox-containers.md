---
layout: post
title: "Root CA certificates for Docker Busybox containers"
excerpt: |
  <p>I use the very useful <a href="https://github.com/progrium/busybox">progrium/busybox image</a> as well as the <a href="https://docs.docker.com/articles/baseimages/#creating-a-simple-base-image-using-scratch">official scratch image</a> for running go services in Docker containers. However, the ima...</p>
modified: 2014-7-22
comments: true
tags: [docker, containers, certificates]
---
I use the very useful [progrium/busybox image](https://github.com/progrium/busybox) as well as the [official scratch image](https://docs.docker.com/articles/baseimages/#creating-a-simple-base-image-using-scratch) for running go services in Docker containers. However, the image does not include certificate trust stores and thus cannot talk to SSL-enabled web services. The application I'm deploying needs to talk to the AWS API which is, of course, SSL-only.

The app throws this error when trying to talk to the DynamoDB API
{% highlight go %}
x509: failed to load system roots and no roots provided
{% endhighlight %}
To fix the issue I mount the host's certificate store in the container. This way there's no need to even keep the root certificates in the image. Golang looks in [a few standard places](http://golang.org/src/pkg/crypto/x509/root_unix.go) for the CA cert bundle. I used `docker run -v '/etc/ssl/certs:/etc/ssl/certs' ...` to mount the host's certs to the container, which prevents the above error.

Another approach would be to use `COPY` instruction to load the certificate store bundle in to the image, thus preventing the need for a volume.
