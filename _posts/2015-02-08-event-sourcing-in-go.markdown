---
layout: post
title: "Event Sourcing in Go"
---

As one of the contributors to [Event Store][eventstore], it should probably not be surprising that sooner or later I'm going to get around to figuring out nice patterns for implementing Event Sourcing in whatever languages I'm working in!

The current holder for the most elegant implementation in my opinion is F# - both [Jérémie Chassaing][jeremie] and [Leo Gorodinski][leo] have very clean examples. Three features of F# which make this elegance possible are immutable record types, discriminated union types and pattern matching. Despite missing these features though, I'm pretty happy with the implementation - it's certainly cleaner than that often seen in C#, for example.

Although often discussed at great length, Event Sourcing is simple. In functional terms, the current state of an [aggregate][aggregate] is a left fold of the previous behaviours it has performed. I'm not going to go into the motivating reasons for this in this post as much has been written about it, not least by [Greg Young][greg] over the years!

The code for this is on [GitHub][repo] - please feel free to pull request any improvements you may have - this is only a first draft!

## Events

The domain I'm going to use is a very restricted subset of a model of a frequent flier account, a subject dear to my heart! Firstly we're going to need some events. In Go we'll just use structures - although they don't have the immutability of record types in F# they're almost as concise to define:

```go
type FrequentFlierAccountCreated struct {
	AccountId         string
	OpeningMiles      int
	OpeningTierPoints int
}

type StatusMatched struct {
	NewStatus Status
}

type FlightTaken struct {
	MilesAdded      int
	TierPointsAdded int
}

type PromotedToGoldStatus struct{}
```

The type `Status` is an enumeration (though is mostly irrelevant to the implementation here). It's defined like this (note the use of `go generate` to produce an implementation of `Stringer` which is less than ideal since it uses the string name rather than a human readable one):

```go
type Status int

const (
	StatusRed    Status = iota
	StatusSilver Status = iota
	StatusGold   Status = iota
)

//go:generate stringer -type=Status
```

## Aggregates

First we're going to define a struct which defines the various pieces of state we're going to need to make decisions for future behaviour. For example, in order to determine whether or not an account should be promoted to gold status when a flight is taken, we'll need a way of keeping track of the number of tier points it has. Note that the state members need not be exported since they'll only be used in methods on the type itself - some read model will be servicing the queries (see [CQRS][cqrs] for more).

Here's the struct:

```go

type FrequentFlierAccount struct {
	id              string
	miles           int
	tierPoints      int
	status          Status
}
```


Next, we'll implement a `Stringer` for `FrequentFlierAccount` such that we can easily print it to the console for the purposes of testing:

```go
func (a FrequentFlierAccount) String() string {
	format := `FrequentFlierAccount: %s
	Miles: %d
	TierPoints: %d
	Status: %s
`
	return fmt.Sprintf(format, a.id, a.miles, a.tierPoints, a.status)
}
```

## Loading from History

There are two different situations a `FrequentFlierAccount` struct is likely to be created - one is in the case where we're opening a new account so have no history to load from, and the other is when we're rehydrating an aggregate from storage to perform some use case with it. For now I'm going to ignore the case of change tracking (I'll come back to it) and focus only on loading from history.

The next thing we're going to need is a history of behaviours from which to load. For the purposes of keeping this implementation in simple, I'm just defining it in the `main()` function, and glossing over loading from storage, deserializing and so forth:

```go
func main() {
	history := []interface{}{
		FrequentFlierAccountCreated{AccountId: "1234567", OpeningMiles: 10000, OpeningTierPoints: 0},
		StatusMatched{NewStatus: StatusSilver},
		FlightTaken{MilesAdded: 2525, TierPointsAdded: 5},
		FlightTaken{MilesAdded: 2512, TierPointsAdded: 5},
		FlightTaken{MilesAdded: 5600, TierPointsAdded: 5},
		FlightTaken{MilesAdded: 3000, TierPointsAdded: 3},
	}

	aggregate := NewFrequentFlierAccountFromHistory(history)
	fmt.Println(aggregate)
}
```

So far so good - everything so far has been type declarations and instantiations. Let's look at the implementation of `NewFrequentFlierAccountFromHistory`:

```go
func NewFrequentFlierAccountFromHistory(events []interface{}) *FrequentFlierAccount {
	state := &FrequentFlierAccount{}
	for _, event := range events {
		switch e := event.(type) {

		case FrequentFlierAccountCreated:
			state.id = e.AccountId
			state.miles = e.OpeningMiles
			state.tierPoints = e.OpeningTierPoints
			state.status = StatusRed

		case StatusMatched:
			state.status = e.NewStatus

		case FlightTaken:
			state.miles = state.miles + e.MilesAdded
			state.tierPoints = state.tierPoints + e.TierPointsAdded

		case PromotedToGoldStatus:
			state.status = StatusGold
		}
	}
	return state
}
```

We simply create the state instance, and then iterate over the history, making the transitions as necessary. This is made succict by the [type switch][typeswitch] construct - the variable `e` has the type of the matched event in each respective case clause. 

That's actually the entire implementation of the loading process. Running the resulting program gives us the expected output:

```bash
$ ./goes
FrequentFlierAccount: 1234567
	Miles: 23637
	TierPoints: 18
	Status: StatusSilver
```

## Change Tracking

The simplicity of this so far probably shouldn't be a surprise - it's only implementing a fold over a list, after all! Now let's look at change tracking and adding actual behaviour to our aggregate. 

The first change we'll make is to separate out the state transitions into their own function rather than being part of the loop which loads from history:

```go
func (state *FrequentFlierAccount) transition(event interface{}) {
	switch e := event.(type) {

	case FrequentFlierAccountCreated:
		state.id = e.AccountId
		state.miles = e.OpeningMiles
		state.tierPoints = e.OpeningTierPoints
		state.status = StatusRed

	case StatusMatched:
		state.status = e.NewStatus

	case FlightTaken:
		state.miles = state.miles + e.MilesAdded
		state.tierPoints = state.tierPoints + e.TierPointsAdded

	case PromotedToGoldStatus:
		state.status = StatusGold
	}
}
```

Now we can modify the `NewFrequentFlierAccountFromHistory` function to use this:

```go
func NewFrequentFlierAccountFromHistory(events []interface{}) *FrequentFlierAccount {
	state := &FrequentFlierAccount{}
	for _, event := range events {
		state.transition(event)
		state.expectedVersion++
	}
	return state
}
```

We'll use a slice in our aggregate state to keep the changes which have been applied to the current instance of the aggregate but not yet persisted. We'll also add the expectedVersion field we increment when loading from history such that we can do [concurrency control][concurrencycontrol] later on.

```go
type FrequentFlierAccount struct {
    //The other members are still here!
    expectedVersion int
	changes         []Event
}
```

Now we'll implement a method on the `FrequentFlierAccount` struct which can be used by our exported API methods to apply an individual change and track it in order that it can be persisted later:

```go
func (state *FrequentFlierAccount) trackChange(event interface{}) {
	state.changes = append(state.changes, event)
	state.transition(event)
}
```

We now have everything in place to implement an actual use case on our aggregate! In this case we'll implement a simple `RecordFlightTaken` method:

```go
//RecordFlightTaken is used to record the fact that a customer has taken a flight
//which should be attached to this frequent flier account. The number of miles and
//tier points which apply are calculated externally.
//
//If recording this flight takes the account over a status boundary, it will
//automatically upgrade the account to the new status level.
func (self *FrequentFlierAccount) RecordFlightTaken(miles int, tierPoints int) {
    //Obviously we should be doing some validation here...

	self.trackChange(FlightTaken{MilesAdded: miles, TierPointsAdded: tierPoints})

	if self.tierPoints > 20 && self.status != StatusGold {
		self.trackChange(PromotedToGoldStatus{})
	}
}
```

We can call this from the `main()` function to modify the account instance we loaded from history:

```go
aggregate := NewFrequentFlierAccountFromHistory(history)
fmt.Println("Before RecordFlightTaken")
fmt.Println(aggregate)

aggregate.RecordFlightTaken(1000, 3)
fmt.Println("After RecordFlightTaken")
fmt.Println(aggregate)
```

Which gives the following output:

```bash
$ ./goes
Before RecordFlightTaken
FrequentFlierAccount: 1234567
	Miles: 23637
	TierPoints: 18
	Status: StatusSilver
	(Expected Version: 6)
	(Pending Changes: 0)

After RecordFlightTaken
FrequentFlierAccount: 1234567
	Miles: 24637
	TierPoints: 21
	Status: StatusGold
	(Expected Version: 6)
	(Pending Changes: 2)
```

## Summary

There isn't a lot of code for implementing this, especially when compared to some implementations in C# which use dynamic calls to event handlers and such. The Go type switch makes it a reasonably concise implementation, even if it does lack the exhaustive pattern match check that a union type would provide in some functional langauges. Whilst immutability would be nice, it doesn't seem particularly idiomatic to Go, so I'm not too concerned about it's loss.

If you have suggestions for how to improve this, please do check out the code on [GitHub][repo] and either comment/open issues there, or get in touch [@jen20 on twitter][twitter]!

[eventstore]: https://github.com/EventStore/EventStore
[jeremie]: https://github.com/thinkbeforecoding/FsUno.Prod
[leo]: https://github.com/eulerfx/DDDInventoryItemFSharp/blob/master/DDDInventoryItemFSharp/InventoryItem.fs
[aggregate]: http://en.wikipedia.org/wiki/Domain-driven_design#Building_blocks_of_DDD
[greg]: http://goodenoughsoftware.net
[concurrencycontrol]: https://groups.google.com/forum/#!searchin/dddcqrs/concurrency$20control/dddcqrs/ngx1qqhk1dA/vLC8GzAmKK0J
[typeswitch]: https://golang.org/doc/effective_go.html#type_switch
[repo]: https://github.com/jen20/go-event-sourcing-sample
[twitter]: https://twitter.com/jen20
