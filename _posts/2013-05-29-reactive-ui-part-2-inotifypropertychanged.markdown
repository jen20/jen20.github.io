---
layout: post
title: "Reactive UI (Part 2) - INotifyPropertyChanged"
---

One of the things that most MVVM frameworks provide is a class implementing
`INotifyPropertyChanged` and so forth in order to allow data binding to work
correctly. The ReactiveUI way of providing this is to provide a base class
named `ReactiveObject` from which you can derive view models.

Let's add a view model for the main window named `MainWindowViewModel` and then
in the constructor of MainWindow (yeah, I know) set the `DataContext` to a new
instance of that:

```csharp
public MainWindow()
{
	InitializeComponent();
	DataContext = new MainWindowViewModel();
}
```

Next, in the MainWindow XAML, we'll add a TextBlock and a TextBox, and
bind them to the same as-yet non-existent property on the ViewModel, for now
using the standard built-in XAML binding strings:

```xml
<StackPanel>
    <TextBlock Text="{Binding Path=SomeText, Mode=OneWay}"></TextBlock>
    <TextBox Text="{Binding Path=SomeText, UpdateSourceTrigger=PropertyChanged}"></TextBox>
</StackPanel>
```

Now we need to add the `SomeText` property to the ViewModel. The ReactiveUI way
to do this is to have a property and a backing field:

```csharp
public class MainWindowViewModel : ReactiveObject
{
	private string _SomeText;

	public string SomeText
	{
		get { return _SomeText; }
		set { this.RaiseAndSetIfChanged(value); }
	}
}
```

Hackery with DotPeek (since I don't have the source to hand) shows that the
implementation of `RaiseAndSetIfChanged` is actually an extension method
defined in the `ReactiveObjectExpressionMixin` class, with the following signature:

```csharp
public static TRet RaiseAndSetIfChanged<TObj, TRet>(
   this TObj This, TRet newValue, [CallerMemberName] string propertyName = null)
      where TObj : ReactiveObject

```

`TObj` can be inferred from the type making the call (provided the `this`
keyword is used to qualify the call), and `TRet` is inferred from the type of
the property. The cunning part here (not unique to Reactive UI) is the use of
`[CallerMemberName]` which is evaluated at compile time to pass the name of the
property as a string (as you can see by decompiling your application). This
prevents us having to use magic strings in our propertyName call, or from
having to use the other overload which uses an expression tree. This overload
works in WPF where we can use reflection to determine which backing field
should be used. On other platforms where this isn't possible, there's an
overload which takes a reference to the backing field which should be set.

Having put this property on the ViewModel, the app runs as expected - the value
of SomeText set by typing in the TextBox is reflected in the TextBlock.

However, using `RaiseAndSetIfChanged` required us to declare the backing
property with the name `_SomeText`. Personally I don't like this convention -
I'd rather the backing properties followed the normal naming convention of
`_someText`. Fortunately this can be changed - the Intellisense says we need to
replace the `RxApp.GetFieldNameForPropertyNameFunc` with one which will do what
we want.

For now I'm going to do that in the constructor of the `App` class (although it
probably belongs in an application bootstrapper):

```csharp
public App()
{
	RxApp.GetFieldNameForPropertyNameFunc = s =>
      string.Format("_{0}{1}", s.Substring(0, 1).ToLowerInvariant(), s.Substring(1));
}
```

After this change, the field name can be changed to `_someText`, and all is
well.

In the next post, I'm going to look at binding commands to buttons.
