---
layout: post
title: "Terminal Colours - A Useful Script"
---

I've been spending a lot more time recently working "full time" in Vim while
writing go and puppet, and so invested a bit of time getting tmux set up to my
liking. As part of this I wanted fancy colours, but the names the terminal
gives them ("colour1", "colour236" - hey, at least they included the "u") are
not that useful.

This simple script however will print a line for each colour in the colour
itself, making it easy to tell them apart!

```bash
#!/usr/bin/env bash
for i in {0..255} ; do
    printf "\e[38;5;${i}mcolour %-5s\e[0m" $i
    if (( $i % 8 == 0 )) ; then printf "\n" ; fi
done
printf "\n"
```

Obviously the colours you actually see will vary depending on terminal
configuration, but on my box configured with Solarized Dark, the output looks
like this:

![Colours Script Output]({{ site.url }}/assets/colours-script.png)
