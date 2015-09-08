---
layout: post
title: "Using HCL - Part 2 - MapStructure"
---

In the [last post][part1], we looked at using the [Hashicorp Configuration
Language][hcl], and promised to reduce some of the verbosity of the code using
the [mapstructure][mapstructure] library also from HashiCorp. Before we
integrate it into our code from the last post, let's look at using the
`mapstructure` library in isolation.

To do that, I've added a new package to the [code][code] from the last post, on
the `part2` branch.

## What is mapstructure?

Mapstructure exists to help convert maps of the form `map[string]interface{}`
to structures. This has a number of uses - one of which is when you have parsed
a file, say JSON or HCL, without being aware upfront of the structure.

The example we use in this article is rather contrived because we actually *do*
know the structure up front and could just use the `json` or `hcl` packages
directly, but it serves OK for demonstrating use of the mapstructure library.

## Getting a map

We could manually make a map of the correct structure, but we may as well just
parse some JSON instead. I've added a file named `mapstructure_test.go` in the
`mapstructureusage` directory for this purpose, and am running the code using
the test runner:

```go
func TestMapStructureDecoding(t *testing.T) {
	input := `{
	"givenName": "Frank",
	"surname": "Sinatra",
	"city": "Hoboken",
	"yearOfBirth": 1915
	}`

	var parsed map[string]interface{}
	if err := json.Unmarshal([]byte(input), &parsed); err != nil {
		t.Error("parse:", err)
	}

	log.Printf("%#v", parsed)
}
```

The output of the `log.Printf` statement (when cleaned up from the test runner
output - this is clearly suboptimal for use as a REPL!), we can see the map:

```go
map[string]interface {}{"yearOfBirth":1915, "givenName":"Frank", "surname":"Sinatra", "city":"Hoboken"}
```

Our use of `json.Unmarshal` here is also suboptimal after a point, though it
should be fine for small quantities of JSON. Instead we should use the really
construct a decoder and use the streaming version if we were reading from a
file rather than a hard-coded string.

## Manually mapping the structure

Now let's say we want to represent our data as a strongly typed `struct` rather
than a map. First let's define the structure:

```go
type Person struct {
	FirstName   string
	Surname     string
	City        string
	YearOfBirth int
}
```

The structure is no surprise - however there are a few important things to
note. The `YearOfBirth` field is of `int` type, and not all of the field names
match their counterparts in JSON (perhaps because we were parsing some
third-party format where the names don't match our internal use cases very
well).

Given the map and the structure, it's straightforward to see a way to turn one
into the other: we need to allocate a `Person` and then go through each of the
fields looking up the value in the map and performing any type conversion that
is necessary, accumulating errors along the way:

```go
func TestMapStructureDecoding(t *testing.T) {
	input := `{
	"givenName": "Frank",
	"surname": "Sinatra",
	"city": "Hoboken",
	"yearOfBirth": 1915
	}`

	var parsed map[string]interface{}
	if err := json.Unmarshal([]byte(input), &parsed); err != nil {
		t.Error("parse:", err)
	}

	var errorAccum *multierror.Error
	var result Person

	if rawFirstName, ok := parsed["givenName"]; ok {
		if firstName, ok := rawFirstName.(string); ok {
			result.FirstName = firstName
		} else {
			errorAccum = multierror.Append(errorAccum, fmt.Errorf("givenName was specified but is not an string"))
		}
	} else {
		errorAccum = multierror.Append(errorAccum, fmt.Errorf("No givenName was found in the input data"))
	}

	if rawSurname, ok := parsed["surname"]; ok {
		if surname, ok := rawSurname.(string); ok {
			result.Surname = surname
		} else {
			errorAccum = multierror.Append(errorAccum, fmt.Errorf("givenName was specified but is not an string"))
		}
	} else {
		errorAccum = multierror.Append(errorAccum, fmt.Errorf("No surname was found in the input data"))
	}

	if rawCity, ok := parsed["city"]; ok {
		if city, ok := rawCity.(string); ok {
			result.City = city
		} else {
			errorAccum = multierror.Append(errorAccum, fmt.Errorf("city was specified but is not an string"))
		}
	} else {
		errorAccum = multierror.Append(errorAccum, fmt.Errorf("No city was found in the input data"))
	}

	if rawYearOfBirth, ok := parsed["yearOfBirth"]; ok {
		if yearOfBirth, ok := rawYearOfBirth.(float64); ok {
			result.YearOfBirth = int(yearOfBirth)
		} else {
			errorAccum = multierror.Append(errorAccum, fmt.Errorf("yearOfBirth was specified but is not an integer"))
		}
	} else {
		errorAccum = multierror.Append(errorAccum, fmt.Errorf("No yearOfBirth was found in the input data"))
	}

	if errorAccum.ErrorOrNil() != nil {
		t.Error(errorAccum.Error())
	} else {
		log.Printf("%+v", result)
	}
}
```

However, it's easy to see how this could spiral out of control with many more
fields to map. It works as expected: if we run with the JSON in the snippet
above, we get our structure:

```go
{FirstName:Frank Surname:Sinatra City:Hoboken YearOfBirth:1915}
```

However, if we, for example, remove surname and make year of birth a string
rather than a number (which gets converted into a `float64` during JSON
parsing), we get our errors list as when we used the `multierror` library
before:

```go
	input := `{
	"givenName": "Frank",
	"city": "Hoboken",
	"yearOfBirth": "1915"
	}`

    // rest of code omitted for brevity
```

Output:

```
2 error(s) occurred:

		* No surname was found in the input data
		* yearOfBirth was specified but is not an integer
```

This is an *awful* lot of code (although there is a good argument that it is
explicit and therefore not a bad thing). Let's look at how we can simplify this
using the `mapstructure` library.

## Using the mapstructure library

The mapstructure library has a `Decode` function which takes a
`map[string]interface{}`, and a pointer to the structure to which to map.
Internally, the `Decode` constructs a `Decoder` with some default options, and
then calls the `Decode` method on that. We'll need to customize some of the
options later but for the simple case let's just go with the package level
`Decode` function:

```go
func TestMapStructureDecoding(t *testing.T) {
	input := `{
	"givenName": "Frank",
	"city": "Hoboken",
	"yearOfBirth": "1915"
	}`

	var parsed map[string]interface{}
	if err := json.Unmarshal([]byte(input), &parsed); err != nil {
		t.Error("parse:", err)
	}

	var result Person
	if err := mapstructure.Decode(parsed, &result); err != nil {
		t.Error(err)
	}

	log.Printf("%+v", result)
}
```

This is rather less code, but the functionality is not yet equivalent.

Note our still-broken input is missing `surname`, and is passing `yearOfBirth`
as a string instead of a number as is expected. Running this test, we see the
error:

```
1 error(s) decoding:

		* 'YearOfBirth' expected type 'int', got unconvertible type 'string'
```

If we fix the type issue in our input:

```go
input := `{
"givenName": "Frank",
"city": "Hoboken",
"yearOfBirth": 1915
}`

// rest of code ommited for brevity
```

We get the following: 

```go
mapstructureusage.Person{FirstName:"", Surname:"", City:"Hoboken", YearOfBirth:1915}
```

Some of this is as we'd expect - the year of birth has been correctly converted
to an `int`, and the `City` field has been mapped correctly. However, `Surname`
was missing from the input, and `FirstName` was there, but named something
else. These are all things our verbose code earlier dealt with.

The second of these issues can be fixed by tagging the fields of the target
structure with the names of the fields expected in the map. This is probably a
good practice anyway, as subsequent field name refactors could change the
behaviour when relying on the implicit naming conventions. Our structure
definition changes to:

```go
type Person struct {
	FirstName   string `mapstructure:"givenName"`
	Surname     string `mapstructure:"surname"`
	City        string `mapstructure:"city"`
	YearOfBirth int    `mapstructure:"yearOfBirth"`
}
```

Note that I've specified the expected name for every field to guard against
future refactoring of the structure, however it is technically only necessary
to provide tags for the fields where the expected name differs from the
conventions.

Now when we run our test from earlier, we get the `FirstName` field populated
with the value specified as `givenName` in the JSON:

```go
mapstructureusage.Person{FirstName:"Frank", Surname:"", City:"Hoboken", YearOfBirth:1915}
```

This still doesn't match the functionality of our verbose manual version
however - we don't have any errors about the missing field. To get this, we'll
need the decoder to track metadata about what it has used and what has been
ignored. For that, we'll need an actual `Decoder` instance instead of using the
package level `Decode` function:

```go
func TestMapStructureDecoding(t *testing.T) {
	input := `{
	"givenName": "Frank",
	"city": "Hoboken",
	"yearOfBirth": 1915,
	"topTenAlbums": 42
	}`

	var parsed map[string]interface{}
	if err := json.Unmarshal([]byte(input), &parsed); err != nil {
		t.Error("parse:", err)
	}

	var result Person
	var metadata mapstructure.Metadata

	decoder, err := mapstructure.NewDecoder(&mapstructure.DecoderConfig{
		Metadata: &metadata,
		Result: &result,
	})
	if err != nil {
		t.Error(err)
	}
	if err := decoder.Decode(parsed); err != nil {
		t.Error(err)
	}

	log.Printf("%#v", result)
	log.Printf("%#v", metadata)
}
```

Running this lets us see the structure of the Metadata:

```
2015/09/08 14:58:39 mapstructureusage.Person{FirstName:"Frank", Surname:"", City:"Hoboken", YearOfBirth:1915}
2015/09/08 14:58:39 mapstructure.Metadata{Keys:[]string{"givenName", "city", "yearOfBirth"}, Unused:[]string{"topTenAlbums"}}
```

We can see the that names of the keys used are in the `Keys` slice, and the
unused ones (note we added one) are listed in the `Unused` slice. There is a
configuration option that causes `Decode` to return an error if there are
Unused keys, though we don't actually need that to replicate the functionality
of our earlier manually-written code.

Now to determine whether missing fields were present, we can test for the list
of required fields having been used. 

```go
func TestMapStructureDecoding(t *testing.T) {
	input := `{
	"givenName": "Frank",
	"city": "Hoboken",
	"yearOfBirth": "1915",
	"topTenAlbums": 42
	}`

	var parsed map[string]interface{}
	if err := json.Unmarshal([]byte(input), &parsed); err != nil {
		t.Error("parse:", err)
	}

	var errorAccum *multierror.Error
	var result Person
	var metadata mapstructure.Metadata

	decoder, err := mapstructure.NewDecoder(&mapstructure.DecoderConfig{
		Metadata: &metadata,
		Result: &result,
	})
	if err != nil {
		t.Error("Failed constructing Decoder")
	}
	if err := decoder.Decode(parsed); err != nil {
        // We don't want the formatting which mapstructure.Error imposes here
		errorAccum = multierror.Append(errorAccum, err.(*mapstructure.Error).WrappedErrors()...)
	}

	fieldsPresent := make(map[string]struct{}, len(metadata.Keys))
	var present struct{}
	for _, fieldName := range metadata.Keys {
		fieldsPresent[fieldName] = present
	}

	for _, fieldName := range []string{"givenName", "surname", "yearOfBirth", "city"} {
		if _, ok := fieldsPresent[fieldName]; !ok {
			errorAccum = multierror.Append(errorAccum, fmt.Errorf("'%s' was not specified", fieldName))
		}
	}

	if errorAccum.ErrorOrNil() != nil {
		t.Error(errorAccum.Error())
	} else {
		log.Printf("%#v", result)
	}
}
```

Now running with our broken input gives the error list we expect:

```
2 error(s) occurred:

		* 'yearOfBirth' expected type 'int', got unconvertible type 'string'
		* 'surname' was not specified
```

If we fix the input, we get the structure, as expected:

Input:

```go
input := `{
"givenName": "Frank",
"surname": "Sinatra",
"city": "Hoboken",
"yearOfBirth": 1915,
"topTenAlbums": 42
}`
```

Output:

```
mapstructureusage.Person{FirstName:"Frank", Surname:"Sinatra", City:"Hoboken", YearOfBirth:1915}
```

## Summary

This is a quick guide of using the mapstructure library for a rather contrived
example, but there are plenty of places where it actually is useful - grep
through the source of [Terraform][tf] for some great examples. Of course, we're
also going to come back to it in the next part for finishing our configuration
sample with HCL!

[part1]: http://jen20.com/2015/09/07/using-hcl-part-1.html "Using HCL - Part 1"
[code]: https://github.com/jen20/hcl-sample "Code for this post"
[tf]: http://terraform.io "Terraform"
[tmpl]: https://github.com/hashicorp/consul-template "Consul Template"
[env]: https://github.com/hashicorp/envconsul "envconsul"
[why]: https://github.com/hashicorp/hcl#why "Why HCL?"
[hcl]: https://github.com/hashicorp/hcl "HCL Repository"
[mapstructure]: https://github.com/mitchellh/mapstructure "MapStructure library"
[me]: https://github.com/hashicorp/go-multierror "MultiError library"
