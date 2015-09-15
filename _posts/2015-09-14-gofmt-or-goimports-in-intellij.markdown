---
layout: post
title: "GoFmt or GoImports on save in IntelliJ"
---

I recently adopted [JetBrains IntelliJ IDEA][idea] IDE with the
rapidly-improving [Go plugin][goplugin] for working on Go code (of course using
[IdeaVim][ideavim]!). I'll post more about using IntelliJ as an IDE for Go in
future (it recently grew support for debugging using Delve).

One of the things the plugin does not set up by default is running `gofmt` (or
`goimports`) upon saving a file - behaviour I had previously had in Macvim.
Restoring this turns out to be reasonably straightforward, with the help of a
JetBrains plugin for IntelliJ named "File Watchers". Having installed this, set
the configuration up like this screenshot:

![File Watcher Configuration](/assets/file-watcher-config.png "File Watcher Configuration")

Now, whenver you save any `.go` file, the `goimports` tool will automatically
fix any unused or missing imports, and format your code for you.

[idea]: https://www.jetbrains.com/idea/ "IntelliJ IDEA"
[ideavim]: https://github.com/JetBrains/ideavim "IdeaVim"
[goplugin]: https://github.com/go-lang-plugin-org/go-lang-idea-plugin "Go Plugin for IntelliJ"
