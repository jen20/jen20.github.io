---
layout: post
title: "Reactive UI (Part 1) - Intro"
permalink: "blog/2013/05/28/reactive-ui-part-1-intro/"
---

Occasionally it becomes necessary for most developers to write something with a
GUI. In this particular case, we need to run software on a touch screen device
with a resistive touchscreen (because of the operating environment in which
everyone wears gloves, and a stylus is impractical). We also need to be able to
control external hardware, primarily via serial ports).

Unfortunately this rules out pretty much every device we could find other than
EPOS terminals running Windows or Linux. Since the vast majority of our
infrastructure is Windows, and thanks to the lack of nice options for building
Windows GUIs we settled on WPF. Consequently, I need to go about re-learning
WPF (haven't touched it for over 2 years, and it's one of those frameworks
where if you don't use it all the time you forget it all!)

Having been bitten before by using frameworks which were either too heavy
(e.g.  MS Prism) or made heavy use of conventions (Caliburn.Micro, though I
should point out now that this was actually through no fault of the library and
they can be turned off), I've decided to investigate using 
[Paul Betts'](http://paulbetts.org) ReactiveUI library
([here](https://github.com/reactiveui/ReactiveUI) on GitHub), and blog about
the learning process in order that hopefully others may benefit from it!

At this stage I'm only interested in WPF, and whilst I assume that much of what
I'll look at will also apply to Silverlight and Metro apps, I'm not actually
certain on that (the MS UI platforms seem to be just as fragmented as the Linux
ones these days - we now, what, like 4 or 5 slightly different XAML platforms!)

ReactiveUI is a fairly small library which uses the Reactive Extensions very
heavily. There are also a number of other compelling reasons to use it, one of
which is the view binding syntax that removes the ridiculous XAML binding
strings (e.g. `{Binding Path=SomeField, Mode=OneWay}`) and replaces them with
programmatic binding in the code behind file. It also has a routing framework
which might simplify building the kind of single-window application I'm looking
at.

I'm going to start by running through some of the samples that come with
ReactiveUI, noting the ReactiveUI way of doing some of the common things needed
for building GUIs using the MVVM pattern, and building a tiny app using these
patterns to refer back to later.

##Versions

Throughout these posts, I'll be using ReactiveUI from NuGet, version 4.6.3,
unless something compelling gets released during the time I'm writing (however,
version 5 looks to be some way off!). 

##Project setup

I'm starting with a new project using the WPF Application template in
VS2012, targetting .NET 4.5, and run it through my standard crap removal
process with Resharper (removing unnecessary boilerplate code such as
<code>using</code> statements that are never used, and references which are
never used).

Adding the ReactiveUI package from NuGet adds quite a few packages on which it
depends, including RX itself, the XAML extensions to RX and extensions to
ReactiveUI such as ReactiveUI-Xaml.

In the next post, I'm going to look at the ReactiveUI way of implementing the
commonly used INotifyPropertyChanged.
