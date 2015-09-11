---
layout: post
title: "User-level Git Exclusions"
---

I recently adopted [JetBrains IntelliJ IDEA][idea] IDE with the
rapidly-improving [Go plugin][goplugin] for working on Go code (of course using
[IdeaVim][ideavim]!). I'll post more about using IntelliJ as an IDE for Go in
future (it recently grew support for debugging using Delve), but the only
downside for me so far is that it generates a directory in each project you
work in to contain caches and so forth.

It is fairly commonplace for `.gitignore` files used by Java projects to ignore
IDEA files along with other common IDE files, but this is not so for Go
repositories. Fortunately, there are two ways to get around this problem
without making pull requests to every project to add ignore patterns for a
fairly non-standard editor!

## Local ignore without .gitignore

Placing the following lines into the `.git/info/exclude` file will stop git
tracking them in a single repository:

```
.idea/
*.iml
```

## Global machine level .gitignore

I actually *never* want to check in IDEA files from *any* repository - unlike
.NET the IDE is not co-mingled with the build system. IDEA will regenerate the
projects for a fresh checkout of a repository without complaint for all project
types that I've worked with (it is possible that there are others not capable
of this though).

Git has a configuration setting named `core.excludesfile` which allows setting
a global .gitignore which is additive to those in each repository. To do that,
the following command is used:

```
git config --global core.excludesfile ~/.dotfiles/global-gitignore
```

And then the the contents of `~/.dotfiles/global-gitignore` is simply:

```
.idea/
*.iml
```

For the rare occasion I actually *do* want to add one of the excluded files,
the standard method of `git add -f file.iml` still works.

Adding this to my configuration management system means I *should* never have
to think about this again, but that's probably not true, hence this post...

[idea]: https://www.jetbrains.com/idea/ "IntelliJ IDEA"
[ideavim]: https://github.com/JetBrains/ideavim "IdeaVim"
[goplugin]: https://github.com/go-lang-plugin-org/go-lang-idea-plugin "Go Plugin for IntelliJ"
