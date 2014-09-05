---
layout: post
title: "Updating to Reactive UI 5"
permalink: "blog/2013/10/16/updating-to-reactive-ui-5/"
---

Today I had to update a WPF application which is using Reactive UI. At the
same time I decided to upgrade from the 4.x version of Reactive UI it was
previously using to 5.2.0 which appears to be the [latest
release](https://github.com/reactiveui/ReactiveUI). This post is just a quick
note of some of the major changes (I'm pretty sure they're already documented
somewhere else as well...)

## Platforms

Reactive UI 5 only targets .NET 4.5. Don't think this is too big an issue - it
does mean no Silverlight, but that's dead anyway so who cares?

## Namespaces and Abstractions

Many of the namespaces have been collapsed down into the root ReactiveUI
namespace. The IOC abstraction has changed quite a bit, so if you had an
adapter for something like Autofac it will likely want updating.
`IMutableDependencyResolver` is the new interface. Personally I'm not using a
container with this stuff so the new bits work without any changes.

## ViewModel Property Declaration

Previously in Reactive UI 4, properties on a ViewModel were often declared like
this:

```csharp
private string _test2;

public string Test2
{
   get { return _test2; }
   set { this.RaiseAndSetIfChanged(vm => vm.Test2, value); }
}
```

The RaiseAndSetIfChanged method found the backing fields by the convention set
in `RxApp.GetFieldNameForPropertyNameFunc` (which almost always needed
overriding if you didn't like Paul's weird property naming convention with an
initial cap :D). It also made tools like ReSharper mad, as it detected the
private field as not being used.

This is no longer supported, the correct way to declare properties in ReactiveUI 5 is this:

```csharp
private string _test2;

public string Test2
{
   get { return _test2; }
   set { this.RaiseAndSetIfChanged(ref _test2, value); }
}
```

Which is just better.

## ReactiveAsyncCommand

Some of the static factory methods have been taken off `ReactiveCommand`, and
`ReactiveAsyncCommand` has gone altogether. The originals are still there, in
the `ReactiveUI.Legacy` namespace, however I don't imagine they'll stay around
forever so converting everything from using `ReactiveAsyncCommand` to the new
`ReactiveCommand` is probably a better idea than using the legacy classes.

## Validation

The validation stuff has gone. It's slated to be re-introduced at some point,
but for any projects using things like `ReactiveValidatedObject`, the original
version is
[here](https://github.com/reactiveui/ReactiveUI/blob/4.6.4/ReactiveUI/Validation.cs).
I'm not quite sure why the old `ReactiveCommand` made it into a legacy
namespace but validation didn't, but that's how it is.

## Scheduler Name

`RxApp.DeferredScheduler` has been renamed `RxApp.MainThreadScheduler`, which
seems more descriptive.

That's most of the big changes that I can spot (at least, they're the things I
had to change to make my old stuff work). By the look of it Reactive UI 5 is a
lot cleaner than the previous version and is still under active development so
hopefully we'll see plenty more where it came from!
