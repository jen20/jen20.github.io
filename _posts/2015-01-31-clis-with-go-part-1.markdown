---
layout: post
title: "CLIs with Go - Part 1"
---

As anyone that follows me on Twitter knows I've been spending a lot of time
writing code in Go recently. There are a few reasons for this, not least some
that I've been working on tooling to bring Azure under control in a more sane
manner than any of the Microsoft-provided tooling, of which more later.

One of the things that Go excels at is writing command line utilities - having
the runtime statically linked makes it very compelling, even with the
additional complexity of distributing compiled binaries for multiple platforms.

## 'flag' Package

Basic command line parsing of options is straightforward in Go using the `flag`
package. For example, the following program takes a couple of arguments of
varying types and dumps them to the command prompt:

```go
package main

import (
	"flag"
	"fmt"
)

type Config struct {
	InMemoryDb  bool
	LogPath     string
	ClusterSize int
}

var config *Config

func init() {
	const (
		inMemoryDbDefault = false
		inMemoryDbDescr   = "Run database entirely in memory. Data is lost when node terminates"

		logPathDefault = "/var/somedb/logs"
		logPathDescr   = "Directory to which to write log files"

		clusterSizeDefault = 3
		clusterSizeDescr   = "The number of nodes to expect in a cluster"
	)
	config = &Config{}
	flag.BoolVar(&config.InMemoryDb, "mem-db", inMemoryDbDefault, inMemoryDbDescr)

	flag.StringVar(&config.LogPath, "log", logPathDefault, logPathDescr)
	flag.StringVar(&config.LogPath, "log-dir", logPathDefault, logPathDescr)

	flag.IntVar(&config.ClusterSize, "cluster-size", clusterSizeDefault, clusterSizeDescr)
}

func main() {
	flag.Parse()

	fmt.Println("In Memory Db?:", config.InMemoryDb)
	fmt.Println("Logs Path:", config.LogPath)
	fmt.Println("Cluster Size:", config.ClusterSize)
}
```

Even a simple program such as this gives us many of the affordances we'd like
from command line utilities. For example, passing the `--help` or `-h` flags to
the program prints some basic usage information:

```bash
$ ./args --help

Usage of ./args:
  -cluster-size=3: The number of nodes to expect in a cluster
  -log="/var/somedb/logs": Directory to which to write log files
  -log-dir="/var/somedb/logs": Directory to which to write log files
  -mem-db=false: Run database entirely in memory. Data is lost when node terminates
```

Passing in value works with either GNU style options (`--` prefixed, my
preferred style for readability) or IEEE style (`-` prefixed):

```bash
$ ./args --cluster-size 5 -log=/var/someprog/ --mem-db

In Memory Db?: true
Logs Path: /var/someprog/
Cluster Size: 5
```

Default values are used if there are no options passed for a particular flag:

```bash
$ ./args --mem-db

In Memory Db?: true
Logs Path: /var/somedb/logs
Cluster Size: 3
```

## 'cli' Package

The `flag` package works well for a wide range of circumstances, but isn't
capable of implementing CLIs which take subcommands in the style of git in
order to group related sets of flags and actions. There are a number of
different third-party packages that implement this, but the one I've been using
comes from Mitchell Hashimoto of Vagrant, Packer, Consul and Terraform fame
(quite a formidable list!).

The `cli` package is go-gettable (`go get github.com/mitchellh/cli`) and
includes a lot more than just an implementation of subcommands. Using it is
fairly straightforward - we'll show writing a program which has subcommands
named `server` and `agent`, where `server` also takes a `--http-port` flag.

The basic type for implementing a command is an interface named `cli.Command`.
To implement this a type requires three methods:

```go
type Command interface {
    // Help should return long-form help text that includes the command-line
    // usage, a brief few sentences explaining the function of the command,
    // and the complete list of flags the command accepts.
    Help() string

    // Run should run the actual command with the given CLI instance and
    // command-line arguments. It should return the exit status when it is
    // finished.
    Run(args []string) int

    // Synopsis should return a one-line, short synopsis of the command.
    // This should be less than 50 characters ideally.
    Synopsis() string
}
```

###Agent Command

So with this in mind, let's create types for the `agent` and `server` commands. Since `agent` has no other parameters, that's the simplest, so we'll start there:

```go
// agent_command.go
package main

import (
	"github.com/mitchellh/cli"
)

type AgentCommand struct {
	Ui cli.Ui
}

func (c *AgentCommand) Run(_ []string) int {
	c.Ui.Output("Would run an agent here")
	return 0
}

func (c *AgentCommand) Help() string {
	return "Run as an agent (detailed help information here)"
}

func (c *AgentCommand) Synopsis() string {
	return "Run as an agent"
}
```

Each of the interface methods is implemented as we'd expect. The return value
from `Run` will become the exit code of the process, so it's important to
return 0 for successful runs and non-zero values for error conditions for the
program to be well behaved.

###cli.Ui Interface

The only surprising element here is the `cli.Ui` type which is declared as a
member of the `AgentCommand` struct implementing the `cli.Command` interface.
This wraps the readers and writers for a terminal to make it easy to prompt for
input, and output to standard out and standard error. Using this is optional
but very useful. The `cli.Ui` interface looks like this:

```go
// Ui is an interface for interacting with the terminal, or "interface"
// of a CLI. This abstraction doesn't have to be used, but helps provide
// a simple, layerable way to manage user interactions.
type Ui interface {
	// Ask asks the user for input using the given query. The response is
	// returned as the given string, or an error.
	Ask(string) (string, error)

	// Output is called for normal standard output.
	Output(string)

	// Info is called for information related to the previous output.
	// In general this may be the exact same as Output, but this gives
	// Ui implementors some flexibility with output formats.
	Info(string)

	// Error is used for any error messages that might appear on standard
	// error.
	Error(string)
}
```

There are a number of useful implementations of this interface which do things
like adding a prefix to the output, colouring the output, making concurrent
output safe and so forth.

###Server Command

Having implemented the `agent` command, let's turn our attention to the
`server` command. The implementation looks reasonably similar - the only real
difference is the addition of the `HttpPort` field on the `ServerCommand`
struct.

```go
package main

import (
	"fmt"
	"github.com/mitchellh/cli"
)

type ServerCommand struct {
	HttpPort int
	Ui       cli.Ui
}

func (c *ServerCommand) Run(_ []string) int {
	c.Ui.Output(fmt.Sprintf("Would run a server here on port %d", c.HttpPort))
	return 0
}

func (c *ServerCommand) Help() string {
	return "Run as a server (detailed help information here)"
}

func (c *ServerCommand) Synopsis() string {
	return "Run as a server"
}
```

###Entry point

Having implemented our simple commands, we can bring them together in order
that they can be launched. In order to do this we need to map the possible
command names onto the `Command` implementations responsible for running them.
This is passed as a `map[string]cli.CommandFactory`, which is an interface
returning an implementation of `cli.Command` and an error which may have
occurred while creating the command.

The main function of our program is shown below. Note the coloured UI wrapper
used for each command.

```go
package main

import (
	"fmt"
	"os"

	"github.com/mitchellh/cli"
)

func main() {

	ui := &cli.BasicUi{
		Reader:      os.Stdin,
		Writer:      os.Stdout,
		ErrorWriter: os.Stderr,
	}

	c := cli.NewCLI("cliexample", "0.0.1")
	c.Args = os.Args[1:]

	c.Commands = map[string]cli.CommandFactory{
		"server": func() (cli.Command, error) {
			return &ServerCommand{
				Ui: &cli.ColoredUi{
					Ui:          ui,
					OutputColor: cli.UiColorBlue,
				},
			}, nil
		},
		"agent": func() (cli.Command, error) {
			return &AgentCommand{
				Ui: &cli.ColoredUi{
					Ui:          ui,
					OutputColor: cli.UiColorGreen,
				},
			}, nil
		},
	}

	exitStatus, err := c.Run()
	if err != nil {
		fmt.Fprintln(os.Stderr, err.Error())
	}

	os.Exit(exitStatus)
}
```

Running this through some basic tests shows that we get a lot of desirable
behaviour for free. Running with no arguments prints a list of available
commands with the synopsis for each:

```bash
$ ./cliexample
usage: cliexample [--version] [--help] <command> [<args>]

Available commands are:
    agent     Run as an agent
    server    Run as a server
```

If we specify `--version`, we get back the version string we passed in when
creating the `cli.Cli`:

```bash
$ ./cliexample --version
1.0.0
```

If we run `--help` in conjunction with a command we get back our detailed help:

```bash
$ ./cliexample --help agent
Run as an agent (detailed help information here)
```

Finally, if we run the command we get output:

```bash
$ ./cliexample agent
Would run an agent here
```

###Arguments to subcommands

We still didn't deal with passing the `--http-port` option to the `server`
command. Luckily we can use our previous knowledge of the `flag` package for
this and parse the remaining flags which get passed to our `Run` method.
Modifying our program to parse the flags is straightforward:

```go
type ServerCommand struct {
	HttpPort int
	Ui       cli.Ui
}

func (c *ServerCommand) Run(args []string) int {
	cmdFlags := flag.NewFlagSet("agent", flag.ContinueOnError)
	cmdFlags.Usage = func() { c.Ui.Output(c.Help()) }

	cmdFlags.IntVar(&c.HttpPort, "http-port", 80, "The port on which to run the HTTP server")
	if err := cmdFlags.Parse(args); err != nil {
		return 1
	}

	c.Ui.Output(fmt.Sprintf("Would run a server here on port %d", c.HttpPort))
	return 0
}
```

At this point we can run and see output like this:

![Command Line Example Outpu]({{ site.url }}/assets/cliexample-output.png)

The code for this is on [GitHub](https://github.com/jen20/cliexample) - in the
next part of this we'll look at some more patterns used for CLIs with this
package.
