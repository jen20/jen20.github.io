---
layout: post
title: "Moving to Go - What I wish I'd known"
---

Quite a few people I know are expressing interest in learning Go, so I decided
to put down a couple of notes about my experience after having had the same
conversation a few times over. None of the points are particularly original and
are mostly here so I can point people at one place when they ask me about it!
Your mileage may vary on any of this stuff and it's in no particular order!

### Go By Example

[Go By Example](https://gobyexample.com) is a great learning resource for the
fundamentals of the language. After that the posts on [Gopher
Acadamy](http://blog.gopheracademy.com) are well worth reading. I'm not aware
of any good print books right now, though I'm sure they exist.

### Test scripts using Go Run

`go run` is awesome - you could almost use it as a scripting language and
it's invaluable for quickly testing snippets of code. Not quite a REPL, but
it works for me.

### Don't fight the $GOPATH

Don't fight the `$GOPATH`. This one is hard as for years I've had code
organized under `~/Code/repo_name`, and the immediate instinct is to keep
things structured in the same way. Whilst the documentation is (or was at
least) somewhat ambiguous about this, the intended method for working with Go
code is to have a single `$GOPATH` across projects.

My `$GOPATH` is set to `~/Code/go`, and I have the following zsh functions
defined to make it easy to move around between different projects:

```bash
cg() {
    cd $GOPATH/src/github.com/$1;
}
```

And the autocomplete for cg:

```bash
#compdef cg
_files -W $GOPATH/src/github.com/ -/
```

This means that I can move around projects like this (since basically all
important code lives on GitHub, except for the standard library):

```bash
$ cg jen20/terraform-provider-azure && pwd
/Users/James/Code/go/src/github.com/jen20/terraform-provider-azure

$ cg MSOpenTech/azure-sdk-for-go && pwd
/Users/James/Code/go/src/github.com/MSOpenTech/azure-sdk-for-go
```

### Vim-Go

Use vim-go. Initially I tried using the IntelliJ plugin for Go, as a long time
IntelliJ and Resharper user I still find the autocompletion to be invaluable
when navigating unfamiliar libraries. However, when I tried it the IntelliJ
plugin didn't work with the single `$GOPATH` detailed above.

There's a nice guide to setting up vim-go
[here](http://blog.gopheracademy.com/vimgo-development-environment/). There are
still a few niggles to fix with it (finding documentation is somewhat hit and
miss from time to time). Turning on the type annotations for the identifier
under the cursor is invaluable.

The only three customizations I have for the vim-go plugin in my `vim.rc` are as
follows:

```vim
let g:go_fmt_fail_silently = 1
let g:go_fmt_command = "gofmt"
let g:go_auto_type_info = 1

" Specific file types
augroup filetypedetect_go
    autocmd FileType go nmap gd <Plug>(go-def)
    autocmd FileType go nmap <Leader>s <Plug>(go-def-split)
    autocmd FileType go nmap <Leader>v <Plug>(go-def-vertical)
    autocmd FileType go nmap <Leader>t <Plug>(go-def-tab)

    autocmd FileType go nmap <Leader>i <Plug>(go-info)

    autocmd FileType go nmap <leader>r <Plug>(go-run)
    autocmd FileType go nmap <leader>b <Plug>(go-build)

    autocmd FileType go nmap <Leader>d <Plug>(go-doc)
augroup END
```

### Dash

Use
[Dash](https://itunes.apple.com/us/app/dash-docs-snippets/id458034879?mt=12) on
OS X. One thing to be said for Visual Studio (when appropriately extended with
ReSharper) is that you rarely have to leave it. The Intellisense docs mean that
it's rarely necessary to go and read the documentation. With Go the docs are
excellent, but are made even better with Dash. It's one of the best uses for
£13 and works across all languages. You can install it via `brew cask` for
added awesome.

### Dependency Management

Don't be tempted to try to replicate complex dependency management tools such
as npm or (god forbid) NuGet. Instead prefer to take fewer dependencies. This
is made easier by an excellent standard library which covers a very wide range
of things very comprehensively.
  
Most libraries are small (one or two files) and can be copied and pasted into
your own source tree, license permitting . `GoDep` appears to be the only thing
approaching an officially sanctioned way, and has a nice mode which vendors
libraries into your own source tree and rewrites the imports.

### Use standard tools like Make

Write Makefiles for anything that isn't a one step `go build`, and consider it
even when that's the only build step. There are very well known arguments for
[using Make](http://hadihariri.com/2014/04/21/build-make-no-more/) over other
tools. This one isn't specific to Go though - most of my .NET projects build
using Make as well these days.
