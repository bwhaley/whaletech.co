---
layout: post
title: "Securing EC2 User Data"
excerpt: |
  <p><a href="http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html">User Data</a> is that feature that allows you to configure new instances at boot using parameters or arbitrary scripts. It's an essential feature for building automated systems, often used to run a management daemon or to configure services.

  <p>Commonly, instances need access to secrets as part of the initialization process. A database connection string, keys to an API, or other sensitive data need to be distributed to the instance, and user data is a handy way to distribute those secrets.</p>

  <p>But user data is not encrypted. It is exposed via the web console, in a file on disk, and to any process running on the instance via the instance metadata. The docs even warn against using it for anything sensitive. Some web app attacks have been known to seek access to user data, hoping to reveal secrets and access info.</p>

  <p>Here's one method to secure those secrets and still preserve the usefulness of user data.</p>
modified: 2015-02-25
tags: [security, userdata, certificates, encryption]
comments: true
---
[User Data](http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html) is that feature that allows you to configure new instances at boot using parameters or arbitrary scripts. It's an essential feature for building automated systems, often used to run a management daemon or to configure services.

Commonly, instances need access to secrets as part of the initialization process. A database connection string, keys to an API, or other sensitive data need to be distributed to the instance, and user data is a handy way to distribute those secrets.

But user data is not encrypted. It is exposed via the web console, in a file on disk, and to any process running on the instance via the instance metadata. The docs even warn against using it for anything sensitive. Some web app attacks have been known to seek access to user data, hoping to reveal secrets and access info.

Here's one method to secure those secrets and still preserve the usefulness of user data.

Generate a public/private keypair using openssl

{% highlight bash %}
openssl req -nodes -x509 -days 10000 -newkey rsa:4096 -keyout private.key -out public.crt -subj '/'
{% endhighlight %}

Bake the private key in to the AMI. I do this with Packer. The provisioner section of the Packer template might look like this:

{% highlight json %}
"provisioners": [
    {
      "type": "file",
      "source": "\\{\\{user private_key_file\\}}",
      "destination": "/tmp/private.key"
    },
    {
      "type": "shell",
      "start_retry_timeout": "10m",
      "inline": [
        "sudo mv /tmp/private.key /etc/ssl/private/private.key"
      ]
    }
  ]
{% endhighlight %}

Use the public key to encrypt the bootstrap script, including secrets. I use `smime` to work around length limits.

{% highlight bash %}
  $ cat /tmp/bootstrap.txt
  # Start two docker containers that need some data
  db="mysql://username:password@somehost:3306/somedb"
  apikey="some_api_secret_key"
  docker run --name "first container" -e apikey=$apikey -d MyImage MyCommand
  docker run --name "second container" -e apikey=$apikey -d MyOtherImage MyOtherCommand
  $ openssl smime --encrypt -aes256 -binary -outform D -in /tmp/bootstrap.txt /tmp/public.key | openssl base64 -e > /tmp/encrypted.b64
{% endhighlight %}

Now embed the encrypted, encoded script in a wrapper that decrypts using the private key, and use that as the user data.

{% highlight bash %}
  #!/usr/bin/env bash -x
  exec >> /tmp/userdata.log 2>&1

  cat << END > /tmp/bootstrap.dat
  <contents of /tmp/encrypted.b64>
  END
  decrypted_blob=$(cat /tmp/bootstrap.dat | openssl base64 -d | openssl smime -decrypt -inform -D binary -inkey /path/to/secret.key
  eval "${decrypted_blob}"
  rm /tmp/bootstrap.dat
  # Could also clean up the secret key here if not needed again
{% endhighlight %}

Note that this is subject to the user data size limit of 16KB.
