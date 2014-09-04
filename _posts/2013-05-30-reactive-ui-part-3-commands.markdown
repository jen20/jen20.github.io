---
layout: post
title: "Reactive UI (Part 3) - Commands"
---

ReactiveUI has a pretty neat implementation of `ICommand` named
`ReactiveCommand`, which takes advantage of RX underpinnings. This post modifies the little app from part 2 by adding a button and binding a command to it.

##Changing the View

The change to the view consist solely of adding a new item to the `StackPanel`
containing all the UI elements so far. That looks like this:

```xml
...
<Button Content="Click Me" Command="{Binding Path=ClickMe}"></Button>
...
```

As you can see, we've used a XAML binding to set the command of the button to
be "ClickMe", which should be on the DataContext. This is all we need to do
here.

##Changing the ViewModel

Obviously to bind to "ClickMe" from the View, we need a command with that name
to exist! We can declare it as a simple public-get, private-set property on our
`MainWindowViewModel`:

```csharp
public ReactiveCommand ClickMe { get; private set; }
```

We need to actually set this somewhere - let's do that in the constructor of
our ViewModel. The constructor for ReactiveCommand is defined as:

```csharp
public ReactiveCommand(IObservable<bool> canExecute = null,
   IScheduler scheduler = null, bool initialCondition = true)
```

For now, the first parameter is the most interesting. It's an `IObservable`
representing whether or not the command can be executed. Awesome, no more
waiting for that to refresh and having UI out of sync with reality!

We'll assume for now that the command can't be executed if there is no text (or
only whitespace) in the `SomeText` property:

```csharp
public MainWindowViewModel()
{
   var canClickMeObservable = this.WhenAny(vm => vm.SomeText, 
      s => !string.IsNullOrWhiteSpace(s.Value));

   ClickMe = new ReactiveCommand(canClickMeObservable);
}
```

We'll look into the slightly odd `WhenAny` syntax later - for now it's
sufficient to know that the first parameters (*n* of them) determine the values
that get passed into the lambda.

This works basically as we'd expect - the button is enabled when non-whitespace
text is entered into the TextBox bound to `SomeText`. However, clicking the
button does nothing.

It turns out, the other neat thing about `ReactiveCommand` is that it's an
`IObservable` in it's own right! So we can subscribe to it, and we'll get an
event fired on the subscription whenever the command is executed. We'll add a
line to the constructor to subscribe, and use a ReactiveUI-provided extension
method such that an `Action<object>` of our choosing is called whenever the
command is executed:

```csharp
//The viewmodel is *not* the ideal place to be doing this!
ClickMe.Subscribe(param => MessageBox.Show("I was clicked"));
```

The subscribe we're using here is definied as an extension method to
`IObservable` in ReactiveUI, and is fairly useful (we can pass in a method
group, for example).

Next we'll go back to the definition of `whenAny()` and figure out what's going
on.
