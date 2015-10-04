---
layout: post
title: "Cloud-Init Configuration Merging"
---


Part of the boot process for Linux instances across many cloud systems
(including AWS and OpenStack) is the [Cloud-Init][ci] system, part of the
Ubuntu project. It [describes itself][docs] as "the defacto multi-distribution
package that handles early initialization of a cloud instance". It has a wide
range of capabilities, and is an important yet under-used piece of
infrastructure.

The idea is straightforward - the source image from which virtual machines
starts cloud-init at boot time, which downloads the configuration from
user-data and then executes commands based on the content of that
configuration. Ahlthough Cloud-Init originated with Ubuntu, it is also used on
Amazon Linux and probably several other distributions, though not all modules
are available on every distribution.

On Amazon Linux, running Cloud-Init is the job of the `cloud-init-local`,
`cloud-init`, `cloud-config` and `cloud-final` init scripts in `/etc/init.d`.
Cloud-Init can be configured to carry out a wide range of tasks such as adding
`yum` or `apt` repositories, writing files, creating users and groups, and
bootstrapping configuration management.

## Cloud-Config Format

The Cloud-config format is yaml, and can contain configuration for different
modules within cloud-init. For example, the following cloud-config can be used
to create a user:

```yaml
#cloud-config

users:
  - name: my_service_account
    gecos: "My Service Account Daemon User"
    inactive: true
    system: true
```

The following cloud-config can be used to add a CA certificate system-wide:

```yaml
#cloud-config

ca-certs:
  remove-defaults: false

  trusted: 
  - |
   -----BEGIN CERTIFICATE-----
   CERTIFICATE MATERIAL GOES HERE
   -----END CERTIFICATE-----
  - |
   -----BEGIN CERTIFICATE-----
   CERTIFICATE MATERIAL GOES HERE
   -----END CERTIFICATE-----
```

Although a cloud-config file or a shell script from user-data can be executed
directly, it is often the case that several configuration files are needed -
for example a shell script and a cloud-config file, which is used to configure
some of the Cloud-Init will read a MIME multi-part message, as is also used for
most email. I'll post more on this in a few days.

Modern versions of Cloud-Init has a system for merging cloud-config files prior
to execution. However, the documentation does not make it clear how to use the
various merging options which are available (yes, I will make a pull request to
improve the documentation when I figure out how to use bazaar). However,
several examples are included in the [tests][tests], and are presented below.

The gist of merging is that you provide one or more options specifying how
dictionaries, arrays and strings are merged. This can either be provided as
`Merge-Type` or `X-Merge-Type` headers in the multi-part stream, or as part of
the cloud-config configuration itself, with the `merge_how` or `merge_type`
keys.

The default merging strategy (likely for reasons of backward compatibility) is
to overwrite in most cases. For example, given the following two cloud-config
files:

```yaml
#cloud-config
run_cmd:
  - bash1
  - bash2
```
  
```yaml
#cloud-config
run_cmd:
  - bash3
  - bash4
```

The default merge strategy gives the following (probably unexpected) result:

```
#cloud-config
run_cmd:
  - bash3
  - bash4
```

To get all of the items included in the merged output, it is necessary to
configure the merge with the following type:

```
list(append)+dict(recurse_array)+str()
```

The examples presented below for easy reference are taken from the Cloud-Init
tests, and demonstrate the majority of desirable merge strategies.

## Cloud-Config merging examples

### Example 1
#### First input source (source1-1.yaml)

```yaml
#cloud-config
Blah: ['blah2']

```

#### Second input source (source1-2.yaml)

```yaml
#cloud-config

Blah: ['b']

merge_how: 'dict(recurse_array,no_replace)+list(append)'
```

#### Merged source (expected1)

```yaml
Blah: ['blah2', 'b']
```


### Example 2
#### First input source (source2-1.yaml)

```yaml
#cloud-config


Blah: 1
Blah2: 2
Blah3: 3
```

#### Second input source (source2-2.yaml)

```yaml
#cloud-config

Blah: 3
Blah2: 2
Blah3: [1]
```

#### Merged source (expected2)

```yaml
Blah: 3
Blah2: 2
Blah3: [1]
```


### Example 3
#### First input source (source3-1.yaml)

```yaml
#cloud-config
Blah: ['blah1']


```

#### Second input source (source3-2.yaml)

```yaml
#cloud-config
Blah: ['blah2']

merge_how: 'dict(recurse_array,no_replace)+list(prepend)'
```

#### Merged source (expected3)

```yaml
Blah: [blah2, 'blah1']
```


### Example 4
#### First input source (source4-1.yaml)

```yaml
#cloud-config
Blah:
  b: 1
```

#### Second input source (source4-2.yaml)

```yaml
#cloud-config
Blah:
  b: null


merge_how: 'dict(allow_delete,no_replace)+list()'
```

#### Merged source (expected4)

```yaml
#cloud-config
Blah: {}
```


### Example 5
#### First input source (source5-1.yaml)

```yaml
#cloud-config


Blah: 1
Blah2: 2
Blah3: 3
```

#### Second input source (source5-2.yaml)

```yaml
#cloud-config

Blah: 3
Blah2: 2
Blah3: [1]


merge_how: 'dict(replace)+list(append)'
```

#### Merged source (expected5)

```yaml
#cloud-config

Blah: 3
Blah2: 2
Blah3: [1]


```


### Example 6
#### First input source (source6-1.yaml)

```yaml
#cloud-config

run_cmds:
  - bash
  - top
```

#### Second input source (source6-2.yaml)

```yaml
#cloud-config

run_cmds:
  - ps
  - vi
  - emacs

merge_type: 'list(append)+dict(recurse_array)+str()'
```

#### Merged source (expected6)

```yaml
#cloud-config

run_cmds:
   - bash
   - top
   - ps
   - vi
   - emacs

```


### Example 7
#### First input source (source7-1.yaml)

```yaml
#cloud-config

users:
  - default
  - name: foobar
    gecos: Foo B. Bar
    primary-group: foobar
    groups: users
    selinux-user: staff_u
    expiredate: 2012-09-01
    ssh-import-id: foobar
    lock-passwd: false
    passwd: $6$j212wezy$7H/1LT4f9/N3wpgNunhsIqtMj62OKiS3nyNwuizouQc3u7MbYCarYeAHWYPYb2FT.lbioDm2RrkJPb9BZMN1O/
  - name: barfoo
    gecos: Bar B. Foo
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin
    ssh-import-id: None
    lock-passwd: true
    ssh-authorized-keys:
      - <ssh pub key 1>
      - <ssh pub key 2>
  - name: cloudy
    gecos: Magic Cloud App Daemon User
    inactive: true
    system: true

```

#### Second input source (source7-2.yaml)

```yaml
#cloud-config

users:
  - bob
  - joe
  - sue
  - name: foobar_jr
    gecos: Foo B. Bar Jr
    primary-group: foobar
    groups: users
    selinux-user: staff_u
    expiredate: 2012-09-01
    ssh-import-id: foobar
    lock-passwd: false
    passwd: $6$j212wezy$7H/1LT4f9/N3wpgNunhsIqtMj62OKiS3nyNwuizouQc3u7MbYCarYeAHWYPYb2FT.lbioDm2RrkJPb9BZMN1O/

merge_how: "dict(recurse_array)+list(append)"
```

#### Merged source (expected7)

```yaml
#cloud-config

users:
  - default
  - name: foobar
    gecos: Foo B. Bar
    primary-group: foobar
    groups: users
    selinux-user: staff_u
    expiredate: 2012-09-01
    ssh-import-id: foobar
    lock-passwd: false
    passwd: $6$j212wezy$7H/1LT4f9/N3wpgNunhsIqtMj62OKiS3nyNwuizouQc3u7MbYCarYeAHWYPYb2FT.lbioDm2RrkJPb9BZMN1O/
  - name: barfoo
    gecos: Bar B. Foo
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin
    ssh-import-id: None
    lock-passwd: true
    ssh-authorized-keys:
      - <ssh pub key 1>
      - <ssh pub key 2>
  - name: cloudy
    gecos: Magic Cloud App Daemon User
    inactive: true
    system: true
  - bob
  - joe
  - sue
  - name: foobar_jr
    gecos: Foo B. Bar Jr
    primary-group: foobar
    groups: users
    selinux-user: staff_u
    expiredate: 2012-09-01
    ssh-import-id: foobar
    lock-passwd: false
    passwd: $6$j212wezy$7H/1LT4f9/N3wpgNunhsIqtMj62OKiS3nyNwuizouQc3u7MbYCarYeAHWYPYb2FT.lbioDm2RrkJPb9BZMN1O/
```


### Example 8
#### First input source (source8-1.yaml)

```yaml
#cloud-config

mounts:
 - [ ephemeral0, /mnt, auto, "defaults,noexec" ]
 - [ sdc, /opt/data ]
 - [ xvdh, /opt/data, "auto", "defaults,nobootwait", "0", "0" ]
 - [ dd, /dev/zero ]
```

#### Second input source (source8-2.yaml)

```yaml
#cloud-config

mounts:
 - [ ephemeral22, /mnt, auto, "defaults,noexec" ]

merge_how: 'dict(recurse_array)+list(recurse_list,recurse_str)+str()'
```

#### Merged source (expected8)

```yaml
#cloud-config

mounts:
 - [ ephemeral22, /mnt, auto, "defaults,noexec" ]
 - [ sdc, /opt/data ]
 - [ xvdh, /opt/data, "auto", "defaults,nobootwait", "0", "0" ]
 - [ dd, /dev/zero ]
```


### Example 9
#### First input source (source9-1.yaml)

```yaml
#cloud-config

phone_home:
 url: http://my.example.com/$INSTANCE_ID/
 post: [ pub_key_dsa, pub_key_rsa, pub_key_ecdsa, instance_id ]
```

#### Second input source (source9-2.yaml)

```yaml
#cloud-config

phone_home:
 url: $BLAH_BLAH

merge_how: 'dict(recurse_str)+str(append)'
```

#### Merged source (expected9)

```yaml
#cloud-config

phone_home:
 url: http://my.example.com/$INSTANCE_ID/$BLAH_BLAH
 post: [ pub_key_dsa, pub_key_rsa, pub_key_ecdsa, instance_id ]
```


### Example 10
#### First input source (source10-1.yaml)

```yaml
#cloud-config

power_state:
 delay: 30
 mode: poweroff
 message: [Bye, Bye]
```

#### Second input source (source10-2.yaml)

```yaml
#cloud-config

power_state:
  message: [Pew, Pew]
  
merge_how: 'dict(recurse_list)+list(append)'
```

#### Merged source (expected10)

```yaml
#cloud-config

power_state:
  delay: 30
  mode: poweroff
  message: [Bye, Bye, Pew, Pew]
  
```


### Example 11
#### First input source (source11-1.yaml)

```yaml
#cloud-config

a: 1
b: 2
c: 3
```

#### Second input source (source11-2.yaml)

```yaml
#cloud-config

b: 4
```

#### Merged source (expected11)

```yaml
#cloud-config

a: 22
b: 4
c: 3
```


### Example 12
#### First input source (source12-1.yaml)

```yaml
#cloud-config

a:
  c: 1
  d: 2
  e:
    z: a
    y: b
```

#### Second input source (source12-2.yaml)

```yaml
#cloud-config

a:
  e:
    y: 2
```

#### Merged source (expected12)

```yaml
#cloud-config

a:
  e:
    y: 2
```

[ci]: https://launchpad.net/cloud-init
[docs]: http://cloudinit.readthedocs.org/en/latest/index.html
[tests]: http://bazaar.launchpad.net/~cloud-init-dev/cloud-init/trunk/files/head:/tests/data/merge_sources/
