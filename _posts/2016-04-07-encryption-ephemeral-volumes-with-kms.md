---
layout: post
title: "Encrypting EC2 ephemeral volumes with LUKS and AWS KMS"
excerpt: "A project I worked on recently has a business requirement to encrypt data at rest. We had a mid-sized Cassandra cluster on EC2 that, for various reasons, stored data on ephemeral volumes. The system had previously relied on Gazzang (now owned by Cloudera) for on-disk encryption, but according to the operations team it was unwieldy to manage and an \"operational bottleneck.\" I can't attest to that as I wasn't involved in the implementation. I was asked to replace it."
modified: 2016-04-07
comments: true
tags: [aws, security, encryption]
---

A project I worked on recently has a business requirement to encrypt data at rest. We had a mid-sized Cassandra cluster on EC2 that, for various reasons, stored data on ephemeral volumes. The system had previously relied on Gazzang (now owned by Cloudera) for on-disk encryption, but according to the operations team it was unwieldy to manage and an "operational bottleneck." I can't attest to that as I wasn't involved in the implementation. I was asked to replace it.

Enter [dm-crypt](https://en.wikipedia.org/wiki/Dm-crypt), and its sidekicks [cryptsetup](https://en.wikipedia.org/wiki/Cryptsetup) and [LUKS](https://en.wikipedia.org/wiki/Linux_Unified_Key_Setup). Perfect for what we needed: an open source disk encryption system built in to the Linux kernel.

Operationally, one challenge with full disk encryption for servers is key management. LUKS/cryptsetup takes a passphrase to be used to generate symmetric keys for encrypting the disk. How can you safely provide the passphrase for mounting the encrypted volume at boot time without operational intervention?

I chose to tackle this with [AWS Key Management Service](https://aws.amazon.com/kms/). The scheme works like this:

1. All Cassandra nodes are members of an IAM role with access to a Cassandra master key. It is the easiest step since the KMS Create Key wizard walks you right through it. I ended up with a key policy that lets my IAM user account administer the key, and the C* IAM role has access to encrypt and decrypt data using the KMS master key.
2. At boot, the C* nodes generate a random passphrase and encrypt it using [KMS envelope encryption](http://docs.aws.amazon.com/kms/latest/developerguide/workflow.html). Store the encrypted passphrase ciphertext on disk.
3. Create a RAID device of all the ephemeral volumes, then use the passphrase to encrypt the volume using LUKS.
4. After a reboot, send the ciphertext to KMS, which decrypts and hands back the passphrase. Use it to open the volume.

The production implementation is chef-ified and somewhat abstract, but I used the following scripts as a proof-of-concept.

## Create a KMS key
You can do this either from the console or via the aws cli tool. It requires a gnarly key policy, which is created for you automatically if you use the console wizard. See an example in the gist linked below.

{% highlight bash %}
$ aws --region us-east-1 kms create-key --policy file://kms_policy.json --description "Cassandra ephemeral disk encryption key"
{% endhighlight %}

Find an example key policy in [this gist](https://gist.github.com/bwhaley/050d342ffc1f7c67acd58357389f9dda#file-kms_policy-json).

## Create and encrypt the ephemeral disks
The script below performs steps 2 & 3 in the list above. Create a RAID array, generate a passphrase, encrypt the RAID device using dm-crypt, and finally create and mount a filesystem on the encrypted device.

{% highlight bash %}
#!/bin/bash
#firstboot.sh
PATH=/bin:/usr/bin:/sbin:/usr/sbin

### Set up raid with two ephemeral devices
yes | mdadm --create --verbose /dev/md0 --level=0 -c256 --raid-devices=2 /dev/xvd{b,c}

# Set readahead
yes | blockdev --setra 65536 /dev/md0

# mdadm config
echo DEVICE /dev/xvd{b,c} > /etc/mdadm.conf
mdadm --detail --scan >> /etc/mdadm.conf

## LUKS
#Generate a random passphrase
passphrase=$(< /dev/urandom tr -dc '_A-Za-z0-9@#%^_\\-\\=+"' | head -c 256 | xargs -0 echo)

# Encrypt the passphrase using KMS. Assumes a key "cassandra" already exists and the IAM role has permissions to use it
# Store the ciphertext in /etc/.luks
key_id='alias/cassandra'
aws --region us-east-1 kms encrypt --key-id ${key_id} --plaintext "${passphrase}" --query CiphertextBlob --output text | base64 -d > /etc/.luks

# Format the RAID device
echo $passphrase | cryptsetup luksFormat /dev/md0

# Get the UUID
UUID=$(cryptsetup luksUUID /dev/md0)

# Open the encrypted volume
echo "$passphrase" | cryptsetup luksOpen UUID=${UUID} cassandra

# the passphrase is no longer needed
unset passphrase

# Do Filesystem stuff
yes | mkfs.ext4 /dev/mapper/cassandra
mkdir -p /var/lib/cassandra
mount /dev/mapper/cassandra /var/lib/cassandra
{% endhighlight %}

## Set up post-boot decryption
At boot we need to decrypt the volume before it's needed by Cassandra. We're using Amazon Linux, which still uses sysv-style init. I put the script in `/etc/init.d/luks-mount` with a symlink from `/etc/rc.3/S15luks`, but this will vary depending on Linux distro. A script to set this up runs just after the encrypted volume is mounted. It looks like this:

{% highlight bash %}
#!/bin/bash
#handle_reboot.sh

# Find the UUID of the luks device
UUID=$(cryptsetup luksUUID /dev/md0)

# Set up the init script
cat <<-EOM > /etc/init.d/luks-mount
#!/bin/bash
# A quickly hacked together script to remount a luks volume at boot

# Get the passphrase from KMS using the ciphertext
passphrase=\$(aws --region us-east-1 kms decrypt --ciphertext-blob fileb:///etc/.luks --output text --query Plaintext | base64 -d)

# Open the LUKS volume
echo "\$passphrase" | cryptsetup luksOpen UUID=${UUID} cassandra

# Mount the volume
mount /dev/mapper/cassandra /var/lib/cassandra
EOM

chmod 755 /etc/init.d/luks-mount

# Symlink from runlevel 3
ln -s /etc/init.d/luks-mount /etc/rc3.d/S15luks
{% endhighlight %}

## Make sure Amazon Linux can boot
A final wrinkle cropped up when Amazon Linux would auto-discover the LUKS volume early in the boot process and would try to decrypt it. At a reboot, it would just prompt for a passphrase and hang indefinitely. The system log looked something like this:

```
0.478204 dracut: luksOpen /dev/md0 luks-9445aa60-9664-4d3b-a65d-bae6576b77bb
/dev/md0 (luks-9445aa60-9664-4d3b-a65d-bae6576b77bb) is password protectedEnter passphrase for /dev/md0:
```

The fix was to prevent the initramfs from discovering and mounting encrypted devices. I did it by removing the crypt module altogether:

{% highlight bash %}
# Omit crypt module from initram so it will not try to mount automatically at boot
sed -i 's/#omit_dracutmodules+=""/omit_dracutmodules+="crypt"/' /etc/dracut.conf

# Regenerate initramfs
dracut --force
{% endhighlight %}

## Conclusion
Is it a perfect scheme? Probably not. But it protects the data at rest as it resides on the host running our EC2 instances, and it avoids ever storing the passphrase in plaintext anywhere. Notice that the passphrase is only ever stored in variables in the bash scripts, and so it's only ever in memory.
