---
layout: post
title: "CLIs with Go - Part 2"
---

It's been a while since the [first part of this post][part1] (I did intend on
writing another part much earlier!) but a recent question made me follow up
with it. The question was about writing tools in the style of the AWS CLI,
with multiple levels of command - in the case of AWS corresponding to each
individual service.

For example, using the AWS CLI (written using Python, tangentially), we can
use the following:

```bash
$ aws
usage: aws [options] <command> <subcommand> [parameters]
aws: error: too few arguments
```

Commands are then subdivided by service (command) and action (subcommand), with
corresponding options. A complete example may look like this:

```bash
$ aws ec2 describe-regions --output=table
----------------------------------------------------------
|                     DescribeRegions                    |
+--------------------------------------------------------+
||                        Regions                       ||
|+-----------------------------------+------------------+|
||             Endpoint              |   RegionName     ||
|+-----------------------------------+------------------+|
||  ec2.eu-west-1.amazonaws.com      |  eu-west-1       ||
||  ec2.ap-southeast-1.amazonaws.com |  ap-southeast-1  ||
||  ec2.ap-southeast-2.amazonaws.com |  ap-southeast-2  ||
||  ec2.eu-central-1.amazonaws.com   |  eu-central-1    ||
||  ec2.ap-northeast-1.amazonaws.com |  ap-northeast-1  ||
||  ec2.us-east-1.amazonaws.com      |  us-east-1       ||
||  ec2.sa-east-1.amazonaws.com      |  sa-east-1       ||
||  ec2.us-west-1.amazonaws.com      |  us-west-1       ||
||  ec2.us-west-2.amazonaws.com      |  us-west-2       ||
|+-----------------------------------+------------------+|
```

The question was how to replicate this in a clean, modular way using the CLI
library. The answer turns out to be relatively straightforward, and actually
turns out with a substantially better user experience than the AWS CLI (I may
experiment at some point with automatically generating a version which uses the
[Go SDK for AWS][sdk-for-go], though that can wait for me to have rather more
free time!).

## Subcommands

First we'll start with the subcommands. This is where you'd add the flag
options using `package flag` from the Go standard library, and in this case
represents operations like `describe-regions`, `create-placement-group` and so
forth. I've chosen to implement four subcommands for this example, each
arranged in a package inside the `ec2` and `s3` top level commands:

```bash
$ tree $GOPATH/jen20/cli-multi-command-example
.
├── ec2
│   └─── commands
│           ├── create_placement_group.go
│           └── describe_instances.go
└── s3
    └─── commands
            ├── website_command.go
            └── s3_command.go
```

We'll look at the `create_placement_group.go` implementation in detail - the
rest are the same but modified accordingly for the command they implement:

```go
package commands

import (
	"fmt"

	"github.com/mitchellh/cli"
)

type CreatePlacementGroupCommand struct {
	Ui cli.Ui
}

func (c *CreatePlacementGroupCommand) Run(args []string) int {
	c.Ui.Output("Would run create-placement-group here")
	c.Ui.Output(fmt.Sprintf("%+v", args))
	return 0
}

func (c *CreatePlacementGroupCommand) Help() string {
	return `Describes one or more of your instances.

If you specify one or more instance IDs, Amazon EC2 returns information for those instances. If you do not specify instance IDs, Amazon EC2 returns information for all relevant instances. If you specify an instance ID that is not valid, an error is returned. If you specify an instance that you do not own, it is not included in the returned results.

Recently terminated instances might appear in the returned results. This interval is usually less than one hour.`
}

func (c *CreatePlacementGroupCommand) Synopsis() string {
	return "Creates a placement group that you launch cluster instances into."
}
```

This is likely familiar to anyone who has read [Part 1][part1] of this series.
We aren't actually doing any of the implementation here though - just printing
a message via the UI abstraction!

## Top-level commands

Within the `ec2` and `s3` packages lives *another* implementation of Command
which represents the top level command, and then has an instance of the
`cli.CLI` in order to deal with subcommands. Here's the contents of
`ec2_command.go`:

```go
package ec2

import (
	"github.com/jen20/cli-multi-command-example/ec2/commands"
	"github.com/mitchellh/cli"
)

type EC2Command struct {
	Ui cli.Ui
}

func (c *EC2Command) Run(args []string) int {
	ec2c := cli.NewCLI("cli-multi-command-example ec2", "")
	ec2c.Args = args

	ec2c.Commands = map[string]cli.CommandFactory{
		"create-placement-group": func() (cli.Command, error) {
			return &commands.CreatePlacementGroupCommand{Ui: c.Ui}, nil
		},
		"describe-instances": func() (cli.Command, error) {
			return &commands.DescribeInstancesCommand{Ui: c.Ui}, nil
		},
	}

	if exitStatus, err := ec2c.Run(); err != nil {
		c.Ui.Error(err.Error())
		return exitStatus
	} else {
		return exitStatus
	}
}

func (c *EC2Command) Help() string {
	return "EC2 commands"
}

func (c *EC2Command) Synopsis() string {
	return "Commands related to the Elastic Compute Cloud (EC2)"
}
```

The interesting parts are in the the `Run` method - we create a new CLI, with a
name corresponding to the command, including the executable name (there is room
for improvement here), and an empty version (more on this shortly). We then
pass on the arguments, register the commands, and run the CLI as before, being
sure to pass the return code down and present any errors via the UI.

The implementation of `S3Command` is effectively the same, with a different
command map and name.

## Entry Point

Now we have commands and subcommands, let's look at the entry point to the
application - the `main` function in `main.go`:

```go
package main

import (
	"fmt"
	"os"

	"github.com/jen20/cli-multi-command-example/ec2"
	"github.com/jen20/cli-multi-command-example/s3"
	"github.com/mitchellh/cli"
)

func main() {
	ui := &cli.BasicUi{
		Reader:      os.Stdin,
		Writer:      os.Stdout,
		ErrorWriter: os.Stderr,
	}

	c := cli.NewCLI("cli-multi-command-example", "0.0.1")
	c.Args = os.Args[1:]

	c.Commands = map[string]cli.CommandFactory{
		"ec2": func() (cli.Command, error) {
			return &ec2.EC2Command{Ui: ui}, nil
		},
		"s3": func() (cli.Command, error) {
			return &s3.S3Command{Ui: ui}, nil
		},
	}

	exitStatus, err := c.Run()
	if err != nil {
		fmt.Fprintln(os.Stderr, err.Error())
	}

	os.Exit(exitStatus)
}
```

This simply maps the two top-level commands to `ec2` and `s3` respectively.
Building and running we now get more helpful information out the box than the
official AWS CLI:

```bash
$ ./cli-multi-command-example
usage: cli-multi-command-example [--version] [--help] <command> [<args>]

Available commands are:
    ec2    Commands related to the Elastic Compute Cloud (EC2)
    s3     Commands related to the Simple Storage Service (S3)
```

With `--version` specified:

```bash
$ ./cli-multi-command-example --version
0.0.1
```

Adding a subcommand, we get:

```bash
$ ./cli-multi-command-example ec2
usage: cli-multi-command-example ec2 [--help] <command> [<args>]

Available commands are:
    create-placement-group    Creates a placement group that you launch cluster instances into.
    describe-instances        Describes one or more of your instances.
```

Finally, running a subcommand with parameters we can see they are passed down
as we expect:

```bash
$ ./cli-multi-command-example ec2 create-placement-group --group-name "my name" --strategy "cluster" --dry-run
Would run create-placement-group here
[--group-name my name --strategy cluster --dry-run]
```

## Caveats

There are two areas that this is less nice than I would like.

1. Having `--version` added to each command is annoying. I have made a pull
   request which suppresses this in the automatically generated help string if
   the CLI instance has an empty string passed as the version number - this
   article was written with [my fork][clifork] of CLI. However, I have opened a
   [pull request][pr] to the official library.
1. Having to specify the name of the executable in the name of each command is
   somewhat annoying. I will investigate ways to reduce the need for this and
   pull request, then update this article accordingly.

Feel free to tweet or mail me with any questions on this article!

[clifork]: https://github.com/jen20/cli "Fork of CLI with --version change"
[pr]: https://github.com/mitchellh/cli/pull/21 "Pull request for --version change"
[aws-cli]: https://aws.amazon.com/cli/ "AWS CLI"
[sdk-for-go]: https://github.com/aws/aws-sdk-go "AWS SDK for Go"
[part1]: http://jen20.com/2015/01/31/clis-with-go-part-1.html "CLIs with Go - Part 1"

