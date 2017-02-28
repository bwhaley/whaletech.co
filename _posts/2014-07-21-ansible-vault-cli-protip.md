---
layout: post
title: "Ansible vault CLI"
excerpt: "<p>Here's a quick tip to make working with encrypted <code>ansible-vault</code> data a little easier. Save the vault password to a file, make an alias of <code>ansible-vault</code> with the path to the saved file. Make two more aliases for decrypt and encrypt, then enjoy fewer keypresses for encrypt..."
modified: 2014-07-21
comments: true
tags: [ansible, security]
---
Here's a quick tip to make working with encrypted `ansible-vault` data a little easier. Save the vault password to a file, make an alias of `ansible-vault` with the path to the saved file. Make two more aliases for decrypt and encrypt, then enjoy fewer keypresses for encrypting and decrypting YAML files.

{% highlight bash %}
$ echo ${vault_pw} > ~/.vaultpw && chmod 600 ~/.vaultpw
$ alias av="ansible-vault --vault-password-file ~/.vaultpw "
$ alias d="decrypt"
$ alias e="encrypt"
$ av d somefile.yml
Decryption successful
$ av e somefile.yml
Encryption successful
{% endhighlight %}
