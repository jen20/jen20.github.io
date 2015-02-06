---
layout: post
title: "Configuring emacs and evil mode for Go development (Part 1)"
---

For years now I've been a heavy user of vim, and have vim key bindings almost
everywhere from Visual Studio to Safari. However, [Jason
Imison](https://twitter.com/jasonimison) of OmniSharp fame piqued my interest in
emacs when he made the switch. In particular the excellent [evil
mode](http://www.emacswiki.org/emacs/Evil) for vim was a critical enabler for
this. 

I was fortunate to have him run through the basics of configuring emacs with me
over a few beers at [Build Stuff 2014](http://buildstuff.lt), so thought I'd
write down the steps in getting to a functional development environment for Go
in the hope that it will help others in future, as I'd already forgotten them
and had to reverse engineer them out of my dotfiles.

This has turned into something of a long post so I've split it up into at least
two parts. This part covers installing and configuring emacs and evil mode, and
getting go-mode installed. The next part will cover the customizations
necessary to get a sensible configuration for Go development.

I'm publishing this as I'm doing it, so the chances of it all being good lisp
are minimal. My config is up [on
Github](https://github.com/jen20/emacs-dotfiles) so feel free to fork and/or
pull request if you have improvements!  ## Environment

I variously run both Mac OS X and Linux, and this post is focused at Mac OS X
users, but most of the configuration should even be portable to Windows (though
untested).

Full disclosure though: I'm writing this post in vim!

## Installing emacs

Emacs actually comes installed on OS X by default, but even on Yosemite the
bundled version is very out of date:

```bash
$ emacs --version
GNU Emacs 22.1.1
Copyright (C) 2007 Free Software Foundation, Inc.
GNU Emacs comes with ABSOLUTELY NO WARRANTY.
You may redistribute copies of Emacs
under the terms of the GNU General Public License.
For more information about these matters, see the file named COPYING.
```

Luckily, for the terminal version of emacs it's homebrew to the rescue (as
usual). Running `brew install emacs` or putting `package { 'emacs': }` in your
Boxen manifest gets you up to date:

```bash
$ emacs --version
GNU Emacs 24.4.1
Copyright (C) 2014 Free Software Foundation, Inc.
GNU Emacs comes with ABSOLUTELY NO WARRANTY.
You may redistribute copies of Emacs
under the terms of the GNU General Public License.
For more information about these matters, see the file named COPYING.
```

As well as terminal mode emacs, there's also a nice GUI version for OS X named,
aptly enough [Emacs for OS X](http://emacsformacosx.com). It's distributed as
an `appdmg`, so the following puppet resource will install it via Boxen:

```puppet
package { 'Emacs':
    provider => 'appdmg',
    source => 'http://emacsformacosx.com/emacs-builds/Emacs-24.4-universal.dmg'
}
```

Ideally I want to be able to use either terminal mode or the GUI with broadly
similar settings, since tmux is too important a piece of my workflow to give
up. I'm told that for people using XMonad and other such tiling window managers
this is less important and the GUI is just fine though.

## First Run

Running `emacs` for the first time in iTerm presents a rather busy looking
welcome screen, and everything has the default config.

![Emacs First Run]({{ site.url }}/assets/emacs-first-run.png)

First thing to understand is the notation of the keyboard shortcuts which are listed there:

- `C-h` means `Ctrl` and `h` as a chord
- `M-x` means `Alt` and `x` as a chord. This is the most important shortcut to
  remember since it allows you to enter commands.
- `C-x C-c` means first press `Ctrl` and `x` as a chord, then `Ctrl` and `x` as
  a chord. It's not necessary to release the `Ctrl` key between these. This is
  the second most important shortcut to remember, since it exits emacs.

If you're running iTerm, it's necessary to change one of the preference
settings to allow meta (alt) keybindings to actually work. Unfortunately this
breaks the input of the hash key on a British Apple keyboard, so I use the US
layout instead. Hence why I tend to write monetary quantities as GBP rather
than £! On Apple keyboards, fortunately this doesn't play around with the
placement of the other punctuation keys (I also use a US layout on PC keyboards
to for the @ and the " symbols to be in the correct place).

![Enable the meta key in iTerm]({{ site.url }}/assets/emacs-first-run.png)

I passionately dislike editors which don't separate out normal from editing
modes - see [emacs pinky](http://c2.com/cgi/wiki?EmacsPinky). So the first
thing I'm going to focus on is getting evil mode installed and running to get
back to proper modal editing à la Vim. Luckily, until evil mode is configured,
vim has highlighting support for emacs lisp, which is the language emacs is
configured in...

## Configuration

Emacs stores it's configuration in `~/.emacs.d/`. The initial config file
(equivalent in a way to `.vimrc`) is named `init.el`. Rather than making this
part of my standard `.dotfiles` repository, I know from previous experience
that it can generate more churn in the dotfiles than I'm used to, so I've made
it a separate git repository:

```bash
$ mkdir ~/.emacs.d/
$ cd ~/.emacs.d/
$ git init
$ touch init.el
$ git add init.el
$ git commit -m "Initial commit"
```

## Package Management

For a while now, Emacs has had a built in package manager which can download
packages from a variety of sources. However, one of the better community led
package repositories, [MELPA](http://melpa.org) isn't in the list by default.
Our first job is to ensure we're using the package manager and to add that
repository to it's list of sources. We also want to add some repositories which
are missing from earlier versions of emacs. Adding the following to the top of
`init.el` achieves this:

```elisp
; Use the package manager
(require 'package)

; Sets package management sources
(add-to-list 'package-archives
             '("melpa" . "http://melpa.org/packages/") t)

(when (< emacs-major-version 24)
  ;; For important compatibility libraries like cl-lib
  (add-to-list 'package-archives 
               '("gnu" . "http://elpa.gnu.org/packages/")))

; Initialize the package manager
(package-initialize)
```

Starting emacs after this, we should be able to find a list of installable
packages using the following (note that RET is the convention in emacs commands
for denoting the &lt;CR&gt; key).

- `M-x package-list-packages RET`

At this point a list of available packages will appear. You'll also notice that
crap gets spewed across the `elpa/` directory inside `~/.emacs.d`. I find no
reason not to commit this to git, but I'm not sure whether that's the intention
of not.

## Installing Evil Mode

To install evil mode, use the following sequence of commands:

- `M-x package-install RET`
- `evil RET`

This will go and download and install the package into some path inside
`~/.emacs.d`. Consequently it can be committed to git and it will be installed
on all machines without having to faff around with vim commands like
`:VundleInstall` across multiple machines. A split pane will open showing the
compilation.

By default evil mode is not enabled even when installed, so we need to add to
the configuration in `init.el` if we want it to be enabled automatically.
Appending the following two lines (I'm still using vim!) does this:

```elisp
; Use evil mode
(require 'evil)
(evil-mode t)
```

A quick note on the `(require 'packagename)` lines: I'm reliably informed that
they aren't strictly necessary and that packages installed via the package
manager are automatically imported. However, I see no harm in being a bit more
verbose in the name of remembering what is going on, especially when new to
emacs lisp! I haven't actually tested whether it's true, either...

At this point we can restart emacs (`C-x C-c` to exit) and it should have evil
mode and feel a bit more familiar. At this point we can navigate around the
home screen using the familiar `hjkl` and switch modes. We can load files using
the familiar `:e filename` command, so we don't have to use vim to edit the
elisp config any more!

There are however a few heavily used (by me at least) key bindings which evil
does not take over. The most notable of these is `C-u`, though it does take
over the corresponding `C-d`. I'm not familiar enough with emacs to know
whether `C-u` is bound to a really important function that should't be
remapped, but `C-u` for page up is baked into my muscle memory enough that I
definitely want evil to use it. Luckily this is a common enough request that
there's a configuration parameter for it:

```elisp
; Give us back Ctrl+U for vim emulation
(setq evil-want-C-u-scroll t)
```

This must appear *before* the call to `(require 'evil)`, else it will have no
effect.

Having added this to the configuration, we could evaluate the configuration
file rather than restart emacs. This turns out to be a very useful cycle when
configuring emacs, and indeed for lisp development overall. To reload, run:

- `M-x eval-buffer RET`

Now we have evil running however, we can use the familiar `:` in place of `M-x`
for entering commands (in normal mode at least). Eliminating RSI one keybinding
at a time!

## C-s for writing

For years I've mapped `C-s` in Vim to save the current buffer. To replicate
that with evil, the following lines do the trick:

```elisp
; Save buffers with Ctrl+S
(global-set-key (kbd "C-s") 'evil-write)
```

I guess it would also be possible to bind to whatever native saving function
exists rather than `evil-write`, but this works for now.

## Escape as a universal cancel

When entering commands into the `M-x`
[minibuffer](https://www.gnu.org/software/emacs/manual/html_node/emacs/Minibuffer.html)
(oh, as an aside I just realised where Jonathan Graham and Sam Aaron [got the
name for their act](http://meta-ex.com)...), I'd rather be able to use Escape
to cancel and get back to the main window. The following function in `init.el`
achieves this:

```elisp
(defun minibuffer-keyboard-quit ()
  "Abort recursive edit.
  In Delete Selection mode, if the mark is active, just deactivate it;
  then it takes a second \\[keyboard-quit] to abort the minibuffer."
  (interactive)
  (if (and delete-selection-mode transient-mark-mode mark-active)
    (setq deactivate-mark  t)
    (when (get-buffer "*Completions*") (delete-windows-on "*Completions*"))
    (abort-recursive-edit)))

(define-key evil-normal-state-map [escape] 'keyboard-quit)
(define-key evil-visual-state-map [escape] 'keyboard-quit)
(define-key minibuffer-local-map [escape] 'minibuffer-keyboard-quit)
(define-key minibuffer-local-ns-map [escape] 'minibuffer-keyboard-quit)
(define-key minibuffer-local-completion-map [escape] 'minibuffer-keyboard-quit)
(define-key minibuffer-local-must-match-map [escape] 'minibuffer-keyboard-quit)
(define-key minibuffer-local-isearch-map [escape] 'minibuffer-keyboard-quit)
(global-set-key [escape] 'evil-exit-emacs-state)
```

Thanks to Stack Overflow for answering that one!

## Modularizing the configuration

It's obvious to see that there's a significant amount of configuration work to
do here to get emacs into shape - we haven't even looked at any language
specific stuff yet! It's likely time to modularize the config. [Stack
Overflow](http://stackoverflow.com/questions/2079095/how-to-modularize-an-emacs-configuration)
once again provides an answer!

In `init.el`, add the following two function definitions below the package
management definitions:

```elisp
(defconst user-init-dir
  (cond ((boundp 'user-emacs-directory)
         user-emacs-directory)
        ((boundp 'user-init-directory)
         user-init-directory)
        (t "~/.emacs.d/")))


(defun load-user-file (file)
  (interactive "f")
  "Load a file in current user's configuration directory"
  (load-file (expand-file-name file user-init-dir)))

; Load configuration modules
(load-user-file "evil.el")
```

Then move the emacs specific config into a file named `evil.el`, which looks
like this so far:

```elisp
; Configure evil mode
; Use C-u for scrolling up
(setq evil-want-C-u-scroll t)

; Bind escape to quit minibuffers
(defun minibuffer-keyboard-quit ()
    "Abort recursive edit.
  In Delete Selection mode, if the mark is active, just deactivate it;
  then it takes a second \\[keyboard-quit] to abort the minibuffer."
    (interactive)
    (if (and delete-selection-mode transient-mark-mode mark-active)
	(setq deactivate-mark  t)
      (when (get-buffer "*Completions*") (delete-windows-on "*Completions*"))
      (abort-recursive-edit)))

(define-key evil-normal-state-map [escape] 'keyboard-quit)
(define-key evil-visual-state-map [escape] 'keyboard-quit)
(define-key minibuffer-local-map [escape] 'minibuffer-keyboard-quit)
(define-key minibuffer-local-ns-map [escape] 'minibuffer-keyboard-quit)
(define-key minibuffer-local-completion-map [escape] 'minibuffer-keyboard-quit)
(define-key minibuffer-local-must-match-map [escape] 'minibuffer-keyboard-quit)
(define-key minibuffer-local-isearch-map [escape] 'minibuffer-keyboard-quit)
(global-set-key [escape] 'evil-exit-emacs-state)

; Use evil mode
(require 'evil)
(evil-mode t)
```

## Miscellaneous appearance configuration

There are various things that I don't like so far about the default appearance.
I don't like the startup message, and I don't like the scroll bars or toolbar
in the GUI version. I've added an `appearance.el` module with the following
content - remember to load it from `init.el`!

```elisp
; Don't display the ugly startup message (particularly ugly in the GUI)
(setq inhibit-startup-message t)

; No toolbar
(tool-bar-mode -1)

; Get rid of the butt ugly OSX scrollbars in GUI
(when (display-graphic-p) (set-scroll-bar-mode nil))
```

The line disabling the scrollbars is interesting - if you evaluate
`(set-scroll-bar-mode nil)` in the terminal version of emacs, it gives an
error. Instead, calling `(display-graphic-p)` will return true if you're in a
GUI, or false otherwise. The `when` function is (apparently) a more idiomatic
one-legged `if`, and supports multiple statements which will be evaluated in
sequence (returning the value of the last).

While we're on the subject of appearance, one of the tips I picked up from
other evil users was to change the colour of the cursor depending on the input
mode.

```elisp
; Set cursor colors depending on mode
(when (display-graphic-p)
  (setq evil-emacs-state-cursor '("red" box))
  (setq evil-normal-state-cursor '("green" box))
  (setq evil-visual-state-cursor '("orange" box))
  (setq evil-insert-state-cursor '("red" bar))
  (setq evil-replace-state-cursor '("red" bar))
  (setq evil-operator-state-cursor '("red" hollow))
)
```

Since the terminal generally controls the cursor when running in terminal mode,
this only works in the GUI.

## Colour Scheme

I have solarized dark set up as my theme in iTerm, so things don't look too bad
in the terminal, but the GUI version is currently damn ugly. Luckily there are
packages for all the common colour schemes, so I'll just use one of those.

The package is installed using `M-x package-install RET solarized-theme RET`,
and then loaded in the `appearance.el` file using:

```elisp
; Use solarized dark (in GUI)
(when (display-graphic-p) (load-theme 'solarized-dark t))
```

Unfortunately the colours in terminals are a bit of a shit show when it comes
to Solarized and emacs, and I've not found an acceptable way to get the colour
scheme working in terminal mode Emacs that doesn't break Vim (which is
expecting an xterm-256color). Luckily it works OK in the GUI though, and the
terminal colours aren't horrific, as my terminal theme is set to Solarized Dark
anyway. I guess until I can figure out how to fix this I'll be using GUI emacs!

## Font in the GUI

I prefer having a reasonably large version of Source Code Pro (patched for
Powerline) as my terminal font, and want to match that in the GUI version of
emacs. The following line in `appearance.el` does that:

```elisp
; Use Source Code Pro 14pt in GUI
(when (display-graphic-p) (set-face-attribute 'default nil :font "Source Code Pro for Powerline-14"))
```

## Go Mode

Although the config so far is by no means perfect, I want to start getting some
of the Go tooling in such that I know what needs fixing! Emacs has the concepts
of "modes", though these are completely different from modes in Vim! In order
to edit Go code productively we'll need to install "go-mode", which is known as
a major mode.

- `M-x package-install RET go-mode RET`

Opening a go file following this shows that we now have syntax highlighting,
which is a good start:

![Go Mode]({{ site.url }}/assets/go-mode-first-run.png)

## What's next?

In the next part of this post (hopefully tomorrow!) I'm going to aim to get the
following working for feature parity with my Vim-go setup:

- integration with `go build` to report errors in real time
- autocompletion
- some form of `ctrl+p`-like file navigation
- some form of Nerdtree-like navigation system
- documentation integration
- snippets for common patterns

In the meantime if you have any suggestions for cool emacs-related stuff I
should look at, please get in touch on Twitter
([@jen20](https://twitter.com/jen20))!
