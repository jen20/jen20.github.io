--- 
layout: post 
title: "Using HCL - Part 1" 
---

Many of the [HashiCorp](https://hashicorp.com) projects use a rather nice
configuration DSL, named "HCL" (an acronym for HashiCorp Configuration
Language). The reasons it was originally created are [documented in the
README][why] in the repository, and I see reason not to adopt it when
building tools in Go (and indeed there may be a good argument for adopting it
on other platforms too).

**tldr; the code is here: [github.com/jen20/hcl-sample][code].**

HCL has seen use in [Terraform][tf], [Consul Template][tmpl], [envconsul][env]
and probably other HashiCorp products so it's likely familiar to many people by
now, but a representative sample of some Terraform configuration using it looks
like this:

```json
provider "aws" {
    region = "${var.aws_region}"
    access_key = "${var.aws_access_key}"
    secret_key = "${var.aws_secret_key}"
}

resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags {
    Name = "Event Store VPC"
  }
}
```

This is fairly readable, and has json equivalent for if it needs to be machine
generated. Unfortunately learning to use the library requires digging through
the innards of Terraform, where the use is rather more advanced than most tools
need due to things like plugins which can specify their own configuration, and
variable interpolation. Alernatively one can look at one of the simpler tools
such as Consul Template which does not demonstrate all of the functionality.

So let's change that!

## Our target

The target of the code presented in this article is to take a string of HCL
configuration as an input, and convert it to a strongly typed Go object
representing the configuration of an application. Although we'll use the code
for a real utility (a backup utility I recently worked on), we'll keep a sample
repository separate so it's obvious what all the code does.

Right now I'm going to ignore the JSON-equivalence, but I'll come back to that
in another post.

An example of our configuration looks like this:

```json
region = "us-west-2"
access_key = "something"
secret_key = "something_else"
bucket = "backups"

directory "config" {
    source_dir = "/etc/eventstore"
    dest_prefix = "escluster/config"
    exclude = []
    pre_backup_script = "before_backup.sh"
    post_backup_script = "after_backup.sh"
    pre_restore_script = "before_restore.sh"
    post_restore_script = "after_restore.sh"
}

directory "data" {
    source_dir = "/var/lib/eventstore"
    dest_prefix = "escluster/a/data"
    exclude = [
        "*.merging"
    ]
    pre_restore_script = "before_restore.sh"
    post_restore_script = "after_restore.sh"
}
```

The Go structure we want to parse this into looks like this (in `config.go`):

```go
package config

type Config struct {
	Region      string
	AccessKey   string
	SecretKey   string
	Bucket      string
	Directories []DirectoryConfig
}

type DirectoryConfig struct {
	Name                  string
	SourceDirectory       string
	DestinationPrefix     string
	ExcludePatterns       []string
	PreBackupScriptPath   string
	PostBackupScriptPath  string
	PreRestoreScriptPath  string
	PostRestoreScriptPath string
}
```

## Unit test
In order to give us something to run, we'll add a test file in our `config` package called `config_test.go` and write a test which outlines our expectations:

```go
package config

import (
	"testing"
	"reflect"
)

func TestConfigParsing(t *testing.T) {
	expected := &Config{
		Region: "us-west-2",
		AccessKey: "something",
		SecretKey: "something_else",
		Bucket: "backups",
		Directories: []DirectoryConfig{
			DirectoryConfig{
				Name: "config",
				SourceDirectory: "/etc/eventstore",
				DestinationPrefix: "escluster/config",
				ExcludePatterns: []string{},
				PreBackupScriptPath: "before_backup.sh",
				PostBackupScriptPath: "after_backup.sh",
				PreRestoreScriptPath: "before_restore.sh",
				PostRestoreScriptPath: "after_restore.sh",
			},
			DirectoryConfig {
				Name: "data",
				SourceDirectory: "/var/lib/eventstore",
				DestinationPrefix: "escluster/a/data",
				ExcludePatterns: []string{"*.merging"},
				PreBackupScriptPath: "",
				PostBackupScriptPath: "",
				PreRestoreScriptPath: "before_restore.sh",
				PostRestoreScriptPath: "after_restore.sh",
			},
		},
	}

	config, err := ParseConfig(testConfig)
	if err != nil {
		t.Error(err)
	}

	if !reflect.DeepEqual(config, expected) {
		t.Error("Config structure differed from expectation")
	}
}

const testConfig = `ommitted for brevity, see above for example`
```

## Getting a parse tree 

The first thing we'll need to do in implementing our `ParseConfig` function is
to parse the input text so we can work on it. The HCL library has a function
named `Parse` for this, which takes a string and gives a parse tree or an
error. We'll pass the error on if there is one, and dump the output to the log
so we can see what we're working with.

```go
import (
	"log"

	"github.com/davecgh/go-spew/spew"
	"github.com/hashicorp/hcl"
)

// Type definitions from above ommitted for brevity

func ParseConfig(hclText string) (Config, error) {
	hclParseTree, err := hcl.Parse(hclText)
	if err != nil {
		return nil, err
	}

	log.Println(spew.Sdump(hclParseTree))

	return nil, nil
}
```

Running the test will show the structure of the `hclParseTree` variable:

```
(*hcl.Object)(0x82035ea50)({
 Key: (string) "",
 Type: (hcl.ValueType) ValueTypeObject,
 Value: ([]*hcl.Object) (len=5 cap=6) {
  (*hcl.Object)(0x82035e600)({
   Key: (string) (len=6) "region",
   Type: (hcl.ValueType) ValueTypeString,
   Value: (string) (len=9) "us-west-2",
   Next: (*hcl.Object)(<nil>)
  }),
  (*hcl.Object)(0x82035e630)({
   Key: (string) (len=10) "access_key",
   Type: (hcl.ValueType) ValueTypeString,
   Value: (string) (len=9) "something",
   Next: (*hcl.Object)(<nil>)
  }),
  (*hcl.Object)(0x82035e660)({
   Key: (string) (len=10) "secret_key",
   Type: (hcl.ValueType) ValueTypeString,
   Value: (string) (len=14) "something_else",
   Next: (*hcl.Object)(<nil>)
  }),
  (*hcl.Object)(0x82035e690)({
   Key: (string) (len=6) "bucket",
   Type: (hcl.ValueType) ValueTypeString,
   Value: (string) (len=7) "backups",
   Next: (*hcl.Object)(<nil>)
  }),
  (*hcl.Object)(0x82035e840)({
   Key: (string) (len=9) "directory",
   Type: (hcl.ValueType) ValueTypeObject,
   Value: ([]*hcl.Object) (len=1 cap=1) {
    (*hcl.Object)(0x82035e810)({
     Key: (string) (len=6) "config",
     Type: (hcl.ValueType) ValueTypeObject,
     Value: ([]*hcl.Object) (len=7 cap=7) {
      (*hcl.Object)(0x82035e6c0)({
       Key: (string) (len=10) "source_dir",
       Type: (hcl.ValueType) ValueTypeString,
       Value: (string) (len=15) "/etc/eventstore",
       Next: (*hcl.Object)(<nil>)
      }),
      (*hcl.Object)(0x82035e6f0)({
       Key: (string) (len=11) "dest_prefix",
       Type: (hcl.ValueType) ValueTypeString,
       Value: (string) (len=16) "escluster/config",
       Next: (*hcl.Object)(<nil>)
      }),
      (*hcl.Object)(0x82035e720)({
       Key: (string) (len=7) "exclude",
       Type: (hcl.ValueType) ValueTypeList,
       Value: ([]*hcl.Object) <nil>,
       Next: (*hcl.Object)(<nil>)
      }),
      (*hcl.Object)(0x82035e750)({
       Key: (string) (len=17) "pre_backup_script",
       Type: (hcl.ValueType) ValueTypeString,
       Value: (string) (len=16) "before_backup.sh",
       Next: (*hcl.Object)(<nil>)
      }),
      (*hcl.Object)(0x82035e780)({
       Key: (string) (len=18) "post_backup_script",
       Type: (hcl.ValueType) ValueTypeString,
       Value: (string) (len=15) "after_backup.sh",
       Next: (*hcl.Object)(<nil>)
      }),
      (*hcl.Object)(0x82035e7b0)({
       Key: (string) (len=18) "pre_restore_script",
       Type: (hcl.ValueType) ValueTypeString,
       Value: (string) (len=17) "before_restore.sh",
       Next: (*hcl.Object)(<nil>)
      }),
      (*hcl.Object)(0x82035e7e0)({
       Key: (string) (len=19) "post_restore_script",
       Type: (hcl.ValueType) ValueTypeString,
       Value: (string) (len=16) "after_restore.sh",
       Next: (*hcl.Object)(<nil>)
      })
     },
     Next: (*hcl.Object)(<nil>)
    })
   },
   Next: (*hcl.Object)(0x82035e9f0)({
    Key: (string) (len=9) "directory",
    Type: (hcl.ValueType) ValueTypeObject,
    Value: ([]*hcl.Object) (len=1 cap=1) {
     (*hcl.Object)(0x82035e9c0)({
      Key: (string) (len=4) "data",
      Type: (hcl.ValueType) ValueTypeObject,
      Value: ([]*hcl.Object) (len=5 cap=5) {
       (*hcl.Object)(0x82035e870)({
        Key: (string) (len=10) "source_dir",
        Type: (hcl.ValueType) ValueTypeString,
        Value: (string) (len=19) "/var/lib/eventstore",
        Next: (*hcl.Object)(<nil>)
       }),
       (*hcl.Object)(0x82035e8a0)({
        Key: (string) (len=11) "dest_prefix",
        Type: (hcl.ValueType) ValueTypeString,
        },
        Next: (*hcl.Object)(<nil>)
       }),
       (*hcl.Object)(0x82035e930)({
        Value: (string) (len=16) "escluster/a/data",
        Next: (*hcl.Object)(<nil>)
       }),
       (*hcl.Object)(0x82035e900)({
        Key: (string) (len=7) "exclude",
        Type: (hcl.ValueType) ValueTypeList,
        Value: ([]*hcl.Object) (len=1 cap=1) {
         (*hcl.Object)(0x82035e8d0)({
          Key: (string) "",

        Key: (string) (len=18) "pre_restore_script",
        Type: (hcl.ValueType) ValueTypeString,
        Value: (string) (len=17) "before_restore.sh",
        Next: (*hcl.Object)(<nil>)
       }),
       (*hcl.Object)(0x82035e960)({
        Key: (string) (len=19) "post_restore_script",
        Type: (hcl.ValueType) ValueTypeString,
        Value: (string) (len=16) "after_restore.sh",
        Next: (*hcl.Object)(<nil>)
       })
      },
      Next: (*hcl.Object)(<nil>)
     })
    },
    Next: (*hcl.Object)(<nil>)
   })
  })
 },
 Next: (*hcl.Object)(<nil>)
})
```

## Getting values out of the parse tree

Looking at this we can clearly see the structure of our configuration. First
let's look at matching the simple string variables at the top of our config:

```go
func ParseConfig(hclText string) (*Config, error) {
	result := &Config{}

	hclParseTree, err := hcl.Parse(hclText)
	if err != nil {
		return nil, err
	}

	if rawRegion := hclParseTree.Get("region", false); rawRegion != nil {
		result.Region = rawRegion.Value.(string)
	}

	log.Printf("%+v\n", result)

	return result, nil
}
```

In this iteration we actually create a `Config` struct and return it (rather
than `nil` as we were doing before). We then use the `Get` method on the
returned parse tree to look for the `region`, in a case-sensitive fashion. If
this is not nil (which means the value is not specified in the tree, at least
not at the top level), we can get the value out by type asserting it to a
`string`.

In addition, we print the structure of our `Config` struct so we can check the
output. In this case, it looks good:

```
&{Region:us-west-2 AccessKey: SecretKey: Bucket: Directories:[]}
```

However, all is not well with this code. There are a few things we must decide:

- What if region is not specified in the configuration text?
- What if region is specified more than once in the configuration text?
- What if region is specified, but is not a string?

Let's expand our code to deal with these situations:

```go
if rawRegion := hclParseTree.Get("region", false); rawRegion != nil {
    if rawRegion.Len() > 1 {
        return nil, fmt.Errorf("Region was specified more than once in the configuration")
    }
    if rawRegion.Type != hclObj.ValueTypeString {
        return nil, fmt.Errorf("Region was specified as an invalid type in the config - expected string, found %s", rawRegion.Type)
    }
    result.Region = rawRegion.Value.(string)
} else {
    return nil, fmt.Errorf("No region was specified in the configuration")
}
```

That's rather a lot of code to deal with one configuration point.  However,
even with all this there are still issues. 

Imagine if we used this code in an application where the configuration file had
many errors. We'd return from `ParseConfig` the first time any error was
encountered - effectively forcing the user to play whack-a-mole with errors as
they fix each one.

Instead what we want is a way of processing all of the configuration together
and then returning all the errors in one hit. Luckily there is another
HashiCorp library which will resolve this, named [go-multierror][me]. Let's
bring in that library now:

```go
var errors *multierror.Error

// Code ommitted for brevity

if rawRegion := hclParseTree.Get("region", false); rawRegion != nil {
    if rawRegion.Len() > 1 {
        errors = multierror.Append(errors, fmt.Errorf("Region was specified more than once in the configuration"))
    } else {
        if rawRegion.Type != hclObj.ValueTypeString {
            errors = multierror.Append(errors, fmt.Errorf("Region was specified as an invalid type in the config - expected string, found %s", rawRegion.Type))
        } else {
            result.Region = rawRegion.Value.(string)
        }
    }
} else {
    errors = multierror.Append(errors, fmt.Errorf("No region was specified in the configuration"))
}

return result, errors.ErrorOrNil()
```

We'll also add handling for the Access Key configuration point:

```go
if rawAccessKey := hclParseTree.Get("access_key", false); rawAccessKey != nil {
    if rawAccessKey.Len() > 1 {
        errors = multierror.Append(errors, fmt.Errorf("Access Key was specified more than once in the configuration"))
    } else {
        if rawAccessKey.Type != hclObj.ValueTypeString {
            errors = multierror.Append(errors, fmt.Errorf("Access Key was specified as an invalid type in the config - expected string, found %s", rawAccessKey.Type))
        } else {
            result.AccessKey = rawAccessKey.Value.(string)
        }
    }
} else {
    errors = multierror.Append(errors, fmt.Errorf("No access key was specified in the configuration"))
}
```

Now, we get a nicely formatted list of errors which have occurred in our code
(if we break our configuration by specifying `region` twice and never
specifying `access_key` at all):

```
2 error(s) occurred:

    * Region was specified more than once in the configuration
    * No access key was specified in the configuration
```

In the next post I'll use [mapstructure][mapstructure] to reduce the amount of
boilerplate code required, and show how to deal with the named configuration
sections.

[code]: https://github.com/jen20/hcl-sample "Code for this post"
[tf]: http://terraform.io "Terraform"
[tmpl]: https://github.com/hashicorp/consul-template "Consul Template"
[env]: https://github.com/hashicorp/envconsul "envconsul"
[why]: https://github.com/hashicorp/hcl#why "Why HCL?"
[mapstructure]: https://github.com/mitchellh/mapstructure "MapStructure library"
[me]: https://github.com/hashicorp/go-multierror "MultiError library"
