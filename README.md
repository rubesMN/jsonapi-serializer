# ~~JSON:API~~ Json Serialization Library

A fast serializer for Ruby Objects *not* in the jsonapi spec.  Just get your stuff fast, nested, and deeply selectable.

Originally this project was called **jsonapi-serializer** originating from a netflix effort.
Some folks forked the project and renamed it to **jsonapi/serializer**.  This fork is one of 200+ forks BUT is a significant 
departure from **jsonapi/serializer**. For now I'm keeping the name but not following the JSON-API format which
most dev organizations dont really do.  

Again, this GEM does not output in JSON-api format, but, keep to the performance goals set out originally
by the netflix team.  The emitted format is what most would expect with the 
following highlights:
* No 'attributes', 'links', nor 'relationship' keys.  Output is simple key/value as we've all been accustomed to as programmers.
* The 'links' key is replaced with '_links' and outputs in HATEOAS format as an array
* Sub-object nesting is allowed but limited to 3 for full serialization with one extra containing ID and links.  This 
  helps large dev organizations from inadvertantly emitting globs and globs of JSON when fields are added
  to downstream nested objects and their associated serializers.  This is the biggest problem with the use
  of RABL, jbuilder, or Draper decorators when they share class/file views which emit json downstream.
* The concept of 'include' has been unified with fields in a nested way now allowing deep selection
  of the fields you want in the most efficient way I could envision.  See tests for examples.
* A self link is added for you by default to every object.  _links can be requested to be removed for 
json size limitations by adding :no_links to the options (which you can grab from your query string)
* Missing or unresolved serializer classes on relationships turns the output into {'id', '_links'}  
* Use of the dynamic serializers results in {'id', 'type', '_links'} output
* Use of the polymorphic identifier results in {'id', 'type', '_links'}
* Over time the performance emphasis got lost as programmers added features to the project.  Notable is large array 
output SQL, when no serializer is identified (or at level 4), turns into obj.subObj_ids query which avoids
  pulling all objects into memory and emitted as {'id', '_links'} 


Also, contributors skipped updating the README file for some reason,.. which is frustrating.  I've removed
support for some odd features which were undocumented.

I would like to thank the Netflix team, the jsonapi-serializer team, and the jsonapi/serializer for their initial work!

# Performance Comparison

We compare serialization times with `ActiveModelSerializer` and alternative
implementations as part of performance tests available at
[jsonapi-serializer/comparisons](https://github.com/jsonapi-serializer/comparisons).

We want to ensure that with every
change on this library, serialization time stays significantly faster than
the performance provided by the alternatives. Please read the performance
article in the `docs` folder for any questions related to methodology.

# Table of Contents

* [Features](#features)
* [Installation](#installation)
* [Usage](#usage)
  * [Rails Generator](#rails-generator)
  * [Model Definition](#model-definition)
  * [Serializer Definition](#serializer-definition)
  * [Object Serialization](#object-serialization)
  * [Compound Document](#compound-document)
  * [Key Transforms](#key-transforms)
  * [Collection Serialization](#collection-serialization)
  * [Caching](#caching)
  * [Params](#params)
  * [Conditional Attributes](#conditional-attributes)
  * [Conditional Relationships](#conditional-relationships)
  * [Specifying a Relationship Serializer](#specifying-a-relationship-serializer)
  * [Sparse Fieldsets](#sparse-fieldsets)
  * [Using helper methods](#using-helper-methods)
* [Performance Instrumentation](#performance-instrumentation)
* [Deserialization](#deserialization)
* [Migrating from Netflix/fast_jsonapi](#migrating-from-netflixfast_jsonapi)
* [Contributing](#contributing)


## Features

* Declaration syntax similar to Active Model Serializer
* Support for `belongs_to`, `has_many` and `has_one`
* Support for compound documents
* Optimized serialization of compound documents
* Advanced fields selection mechanism regardless of where in the json it is emitted
* Caching

## Requirements
Ruby 2.3.5+

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'jsonapi-serializer'
```

Execute:

```bash
$ bundle install
```

## Usage

### Rails Generator
You can use the bundled generator if you are using the library inside of
a Rails project:

    rails g serializer Movie name year

This will create a new serializer in `app/serializers/movie_serializer.rb`. Generated 
serializers arent going to help much.. use the below examples.

### Example Model for our doc purposes

```ruby
class Movie
  attr_accessor :id, :name, :year, :actors, :creator

  def url(obj = nil)
    @url ||= FFaker::Internet.http_url
    return @url if obj.nil?

    @url + '?' + obj.hash.to_s
  end

end
class Actor < User
  attr_accessor :movies
  
  def bio_link
    "https://www.imdb.com/name/nm0000098/"
  end
  
  def favorite_movie
    movies.present? ? movies[0] : nil
  end

end
class User
  attr_accessor :uid, :first_name, :last_name, :email

end
```

### Serializer Definition Example

```ruby
class MovieSerializer
  include JSONAPI::Serializer

  set_system :movie_service
  set_type :movie  # highly recommended 
  attributes :name # can be list of attributes comma separated
  attribute :release_year do |object|
    object.year # way to return the attr/obj to serialize from movie object 
  end
  link rel: :self, link_method_name: :url # you can override the auto-generated :self link
  has_many :actors  # looks for class ActorsSerializer
  belongs_to :creator, serializer: UserSerializer
end

class ActorSerializer < UserSerializer # normally dont do inheritance.. couple side affects in that
  include JSONAPI::Serializer
  set_type :actor # recommended 

  has_many :movies, key: :played_movies # using key is another way to change the output json key

  has_one :favorite_movie, serializer: :movie

  link rel: :bio, system: :IMDB, link_method_name: :bio_link
  link rel: :hair_salon_discount do |obj|
    "www.somesalon.com/#{obj.uid}"
  end
end
class UserSerializer
  include JSONAPI::Serializer

  set_id :uid
  attributes :first_name, :last_name, :email

end
```

### Object Serialization

#### Return a hash
```ruby
hash = MovieSerializer.new(movie).serializable_hash
```

#### Return Serialized JSON
```ruby
json_string = MovieSerializer.new(movie).serializable_hash.to_json
```

#### In Rails application controller 
```ruby
options = {}
options[:fields] = JSON.parse(params[:fields])
options[:params] = {
  current_user: current_user
}
options[:no_links] = params[:no_links] unless params[:no_links].blank?
respond_with MovieSerializer.new(movie, options).serializable_hash
```

#### Serialized Output
Notice that we've defined an infinite loop that is shorted out due to the nesting limitations.
Actors contain movies which have actors and so on.. 

```json
{
  "id": "ab832b78-2af8-468e-85b6-943bad155fa5",
  "name": "Legend of Blonde Friday",
  "release_year": "1948",
  "actors": [
    {
      "id": "8447b895-79a5-4860-b5b5-901a7f7e441b",
      "first_name": "Lenore",
      "last_name": "Bauch",
      "email": "darcey@schamberger.co.uk",
      "played_movies": [
        {
          "id": "ab832b78-2af8-468e-85b6-943bad155fa5",
          "name": "Legend of Blonde Friday",
          "release_year": "1948",
          "creator": {
            "id": "e4bdf0fa-107f-47c8-8db8-4ff4aa4a4ad3",
            "first_name": "Sierra",
            "last_name": "Nikolaus",
            "email": "ela.emmerich@walter.ca",
            "_links": [
              {
                "rel": "self",
                "system": "",
                "type": "GET",
                "href": "/users/e4bdf0fa-107f-47c8-8db8-4ff4aa4a4ad3"
              }
            ]
          },
          "actors": [
            {
              "id": "8447b895-79a5-4860-b5b5-901a7f7e441b",
              "first_name": "Lenore",
              "last_name": "Bauch",
              "email": "darcey@schamberger.co.uk",
              "played_movies": [
                {
                  "id": "ab832b78-2af8-468e-85b6-943bad155fa5",
                  "_links": [
                    {
                      "rel": "self",
                      "system": "",
                      "type": "GET",
                      "href": "/movies/ab832b78-2af8-468e-85b6-943bad155fa5"
                    }
                  ]
                }
              ],
              "favorite_movie": {
                "id": "ab832b78-2af8-468e-85b6-943bad155fa5",
                "_links": [
                  {
                    "rel": "self",
                    "system": "",
                    "type": "GET",
                    "href": "/movies/ab832b78-2af8-468e-85b6-943bad155fa5"
                  }
                ]
              },
              "_links": [
                {
                  "rel": "self",
                  "system": "",
                  "type": "GET",
                  "href": "/actors/8447b895-79a5-4860-b5b5-901a7f7e441b"
                },
                {
                  "rel": "bio",
                  "system": "IMDB",
                  "type": "GET",
                  "href": "https://www.imdb.com/name/nm0000098/"
                },
                {
                  "rel": "hair_salon_discount",
                  "system": "",
                  "type": "GET",
                  "href": "www.somesalon.com/8447b895-79a5-4860-b5b5-901a7f7e441b"
                }
              ]
            }
          ],
          "_links": [
            {
              "rel": "self",
              "system": "imdb",
              "type": "GET",
              "href": "http://armstrong.name"
            }
          ]
        }
      ],
      "favorite_movie": {
        "id": "ab832b78-2af8-468e-85b6-943bad155fa5",
        "name": "Legend of Blonde Friday",
        "release_year": "1948",
        "actors": [
          {
            "id": "8447b895-79a5-4860-b5b5-901a7f7e441b",
            "first_name": "Lenore",
            "last_name": "Bauch",
            "email": "darcey@schamberger.co.uk",
            "played_movies": [
              {
                "id": "ab832b78-2af8-468e-85b6-943bad155fa5",
                "_links": [
                  {
                    "rel": "self",
                    "system": "imdb",
                    "type": "GET",
                    "href": "/movies/ab832b78-2af8-468e-85b6-943bad155fa5"
                  }
                ]
              }
            ],
            "favorite_movie": {
              "id": "ab832b78-2af8-468e-85b6-943bad155fa5",
              "_links": [
                {
                  "rel": "self",
                  "system": "",
                  "type": "GET",
                  "href": "/movies/ab832b78-2af8-468e-85b6-943bad155fa5"
                }
              ]
            },
            "_links": [
              {
                "rel": "self",
                "system": "",
                "type": "GET",
                "href": "/actors/8447b895-79a5-4860-b5b5-901a7f7e441b"
              },
              {
                "rel": "bio",
                "system": "IMDB",
                "type": "GET",
                "href": "https://www.imdb.com/name/nm0000098/"
              },
              {
                "rel": "hair_salon_discount",
                "system": "",
                "type": "GET",
                "href": "www.somesalon.com/8447b895-79a5-4860-b5b5-901a7f7e441b"
              }
            ]
          }
        ],
        "creator": {
          "id": "e4bdf0fa-107f-47c8-8db8-4ff4aa4a4ad3",
          "first_name": "Sierra",
          "last_name": "Nikolaus",
          "email": "ela.emmerich@walter.ca",
          "_links": [
            {
              "rel": "self",
              "system": "",
              "type": "GET",
              "href": "/users/e4bdf0fa-107f-47c8-8db8-4ff4aa4a4ad3"
            }
          ]
        },
        "_links": [
          {
            "rel": "self",
            "system": "imdb",
            "type": "GET",
            "href": "http://armstrong.name"
          }
        ]
      },
      "_links": [
        {
          "rel": "self",
          "system": "",
          "type": "GET",
          "href": "/actors/8447b895-79a5-4860-b5b5-901a7f7e441b"
        },
        {
          "rel": "bio",
          "system": "IMDB",
          "type": "GET",
          "href": "https://www.imdb.com/name/nm0000098/"
        },
        {
          "rel": "hair_salon_discount",
          "system": "",
          "type": "GET",
          "href": "www.somesalon.com/8447b895-79a5-4860-b5b5-901a7f7e441b"
        }
      ]
    }
  ],
  "creator": {
    "id": "e4bdf0fa-107f-47c8-8db8-4ff4aa4a4ad3",
    "first_name": "Sierra",
    "last_name": "Nikolaus",
    "email": "ela.emmerich@walter.ca",
    "_links": [
      {
        "rel": "self",
        "system": "",
        "type": "GET",
        "href": "/users/e4bdf0fa-107f-47c8-8db8-4ff4aa4a4ad3"
      }
    ]
  },
  "_links": [
    {
      "rel": "self",
      "system": "",
      "type": "GET",
      "href": "http://armstrong.name"
    }
  ]
}

```

#### The Optionality of `set_type`
By default fast_jsonapi will try to figure the type based on the name of the serializer class. For example `class MovieSerializer` will automatically have a type of `:movie`. If your serializer class name does not follow this format, you have to manually state the `set_type` at the serializer.

### Key Transforms
By default fast_jsonapi underscores the key names. It supports the same key transforms that are supported by AMS. Here is the syntax of specifying a key transform

```ruby
class MovieSerializer
  include JSONAPI::Serializer

  # Available options :camel, :camel_lower, :dash, :underscore(default)
  set_key_transform :camel
end
```
Here are examples of how these options transform the keys

```ruby
set_key_transform :camel # "some_key" => "SomeKey"
set_key_transform :camel_lower # "some_key" => "someKey"
set_key_transform :dash # "some_key" => "some-key"
set_key_transform :underscore # "some_key" => "some_key"
```

### Attributes
Attributes are defined using the `attributes` method.  This method is also aliased as `attribute`, which is useful when defining a single attribute.

By default, attributes are read directly from the model property of the same name.  In this example, `name` is expected to be a property of the object being serialized:

```ruby
class MovieSerializer
  include JSONAPI::Serializer

  attribute :name
end
```

Custom attributes that must be serialized but do not exist on the model can be declared using Ruby block syntax:

```ruby
class MovieSerializer
  include JSONAPI::Serializer

  attributes :name, :year

  attribute :name_with_year do |object|
    "#{object.name} (#{object.year})"
  end
end
```

The block syntax can also be used to override the property on the object:

```ruby
class MovieSerializer
  include JSONAPI::Serializer

  attribute :name do |object|
    "#{object.name} Part 2"
  end
end
```

Attributes can also use a different name by passing the original method or accessor with a proc shortcut:

```ruby
class MovieSerializer
  include JSONAPI::Serializer

  attributes :name

  attribute :released_in_year, &:year
end
```

### Links Per Object
Links are defined using the `link` method.  Links emit themselves using the a format which allows programmers to make follow on API calls.  Links have the following fields 
* rel - short for relationship.  Here you name and effectively define the semantics of what the endpoint does.
* system - what category of APIs or what external system does this API get called on.  Can be used to provide hostnames, SOA service identifiers, or used to do client-side load balancing.
* type - GET, POST, PUT or some other transport identification
* href - relative or absolute URL to the API

You can configure the method from which to get the href endpoint or provide a block to emit the value.  Both mechanisms pass in the object which you are serializing (movie in this example)
and optionally params which are passed from one serializer to the next as we nest sub-objects.

```ruby
class MovieSerializer
  include JSONAPI::Serializer

  link rel: :self, link_method_name: :url

  link :custom_url do |object|
    "https://movies.com/#{object.name}-(#{object.year})"
  end

  link :personalized_url do |object, params|
    "https://movies.com/#{object.name}-#{params[:current_user].reference_code}"
  end
end
```


### Compound Document

Support for top-level and nested associations merely through the inclusion of the relationships (subject to conditionals) within the serializer.  Other
json 'view' frameworks work this way,.. why not this one. 

### Collection Serialization

```ruby
hash = MovieSerializer.new(movies, options).serializable_hash
json_string = MovieSerializer.new(movies, options).serializable_hash.to_json
```

#### Control Over Collection Serialization

You can use `is_collection` option to have better control over collection serialization.

If this option is not provided or `nil` autodetect logic is used to try understand
if provided resource is a single object or collection.

Autodetect logic is compatible with most DB toolkits (ActiveRecord, Sequel, etc.) but
**cannot** guarantee that single vs collection will be always detected properly.

```ruby
options[:is_collection]
```

was introduced to be able to have precise control this behavior

- `nil` or not provided: will try to autodetect single vs collection (please, see notes above)
- `true` will always treat input resource as *collection*
- `false` will always treat input resource as *single object*

### Caching

To enable caching, use `cache_options store: <cache_store>`:

```ruby
class MovieSerializer
  include JSONAPI::Serializer

  # use rails cache with a separate namespace and fixed expiry
  cache_options store: Rails.cache, namespace: 'jsonapi-serializer', expires_in: 1.hour
end
```

`store` is required can be anything that implements a
`#fetch(record, **options, &block)` method:

- `record` is the record that is currently serialized
- `options` is everything that was passed to `cache_options` except `store`, so it can be everything the cache store supports
- `&block` should be executed to fetch new data if cache is empty

So for the example above it will call the cache instance like this:

```ruby
Rails.cache.fetch(record, namespace: 'jsonapi-serializer', expires_in: 1.hour) { ... }
```

#### Caching and Sparse Fieldsets

If caching is enabled and fields are provided to the serializer, the fieldset will be appended to the cache key's namespace.

For example, given the following serializer definition and instance:
```ruby
class ActorSerializer
  include JSONAPI::Serializer

  attributes :first_name, :last_name

  cache_options store: Rails.cache, namespace: 'jsonapi-serializer', expires_in: 1.hour
end

serializer = ActorSerializer.new(actor, { fields: [ {actor: [:first_name] } })
```

The following cache namespace will be generated: `'jsonapi-serializer-fieldset:actor:first_name'` and the key will be the actor's id.

### Params

In some cases, attribute values might require more information than what is
available on the record, for example, access privileges or other information
related to a current authenticated user. The `options[:params]` value covers these
cases by allowing you to pass in a hash of additional parameters necessary for
your use case.

Leveraging the new params is easy, when you define a custom id, attribute or
relationship with a block you opt-in to using params by adding it as a block
parameter.

```ruby
class MovieSerializer
  include JSONAPI::Serializer

  set_id do |movie, params|
    # in here, params is a hash containing the `:admin` key
    params[:admin] ? movie.owner_id : "movie-#{movie.id}"
  end

  attributes :name, :year
  attribute :can_view_early do |movie, params|
    # in here, params is a hash containing the `:current_user` key
    params[:current_user].is_employee? ? true : false
  end

  belongs_to :primary_agent do |movie, params|
    # in here, params is a hash containing the `:current_user` key
    params[:current_user].is_employee? ? true : false
  end
end

# ...
current_user = User.find(cookies[:current_user_id])
serializer = MovieSerializer.new(movie, {params: {current_user: current_user}})
serializer.serializable_hash
```

Custom attributes and relationships that only receive the resource are still possible by defining
the block to only receive one argument.

### Conditional Attributes

Conditional attributes can be defined by passing a Proc to the `if` key on the `attribute` method. Return `true` if the attribute should be serialized, and `false` if not. The record and any params passed to the serializer are available inside the Proc as the first and second parameters, respectively.

```ruby
class MovieSerializer
  include JSONAPI::Serializer

  attributes :name, :year
  attribute :release_year, if: Proc.new { |record|
    # Release year will only be serialized if it's greater than 1990
    record.release_year > 1990
  }

  attribute :director, if: Proc.new { |record, params|
    # The director will be serialized only if the :admin key of params is true
    params && params[:admin] == true
  }

  # Custom attribute `name_year` will only be serialized if both `name` and `year` fields are present
  attribute :name_year, if: Proc.new { |record|
    record.name.present? && record.year.present?
  } do |object|
    "#{object.name} - #{object.year}"
  end
end

# ...
current_user = User.find(cookies[:current_user_id])
serializer = MovieSerializer.new(movie, { params: { admin: current_user.admin? }})
serializer.serializable_hash
```

### Conditional Relationships

Conditional relationships can be defined by passing a Proc to the `if` key. Return `true` if the relationship should be serialized, and `false` if not. The record and any params passed to the serializer are available inside the Proc as the first and second parameters, respectively.

```ruby
class MovieSerializer
  include JSONAPI::Serializer

  # Actors will only be serialized if the record has any associated actors
  has_many :actors, if: Proc.new { |record| record.actors.any? }

  # Owner will only be serialized if the :admin key of params is true
  belongs_to :owner, if: Proc.new { |record, params| params && params[:admin] == true }
end

# ...
current_user = User.find(cookies[:current_user_id])
serializer = MovieSerializer.new(movie, { params: { admin: current_user.admin? }})
serializer.serializable_hash
```

### Specifying a Relationship Serializer

In many cases, the relationship can automatically detect the serializer to use.

```ruby
class MovieSerializer
  include JSONAPI::Serializer

  # resolves to StudioSerializer
  belongs_to :studio
  # resolves to ActorSerializer
  has_many :actors
end
```

At other times, such as when a property name differs from the class name, you may need to explicitly state the serializer to use.  You can do so by specifying a different symbol or the serializer class itself (which is the recommended usage):

```ruby
class MovieSerializer
  include JSONAPI::Serializer

  # resolves to MovieStudioSerializer
  belongs_to :studio, serializer: :movie_studio
  # resolves to PerformerSerializer
  has_many :actors, serializer: PerformerSerializer
end
```

For more advanced cases, such as polymorphic relationships and Single Table Inheritance, you may need even greater control to select the serializer based on the specific 
object or some specified serialization parameters.  Doing a dynamically constructed serializer will result in lowered serialization performance and currently only
allowed for has_one and belongs_to relationships.  I welcome someone volunteering to make this work for has_many relationships, however, its relatively easy to replicate 
this behavior using a generic serializer and add conditional attributes and relationships.  To use this, define the serializer as a `Proc`:

```ruby
class MovieSerializer
  include JSONAPI::Serializer

  has_one :creator, serializer: Proc.new do |record, params|
    if record.actor?
      ActorSerializer
    else
      UserSerializer
    end
  end
end
```

### Sparse Fieldsets

Attributes and relationships can be selectively returned by using the `fields` option which applies to attributes and relationships.

```ruby
class MovieSerializer
  include JSONAPI::Serializer

  set_system :movie_service
  set_type :movie  # highly recommended 
  attributes :name 
  attribute :release_year do |object|
    object.year # way to return the attr/obj to serialize from movie object 
  end
  link rel: :self, link_method_name: :url # you can override the auto-generated :self link
  has_many :actors  # looks for class ActorsSerializer
  belongs_to :creator, serializer: UserSerializer
end

class ActorSerializer < UserSerializer # normally dont do inheritance.. couple side affects in that
  set_type :actor # recommended 

  has_many :movies, key: :played_movies # using key is another way to change the output json key

  has_one :favorite_movie, serializer: :movie

  link rel: :bio, system: :IMDB, link_method_name: :bio_link
  link rel: :hair_salon_discount do |obj|
    "www.somesalon.com/#{obj.uid}"
  end
end

class UserSerializer
  include JSONAPI::Serializer

  set_id :uid
  attributes :first_name, :last_name, :email

end
options = {}
options[:fields] =  [:name,
                    :release_year,
                    {creator: [:first_name, :last_name]},
                    {actors: [:first_name,
                              :email,
                              {played_movies: [:name,
                                               :release_year,
                                               {creator: [:email]}]},
                              {favorite_movie: [:name]}]}
]
serializer = MovieSerializer.new(movie, options)
serializer.serializable_hash
```

You have no option with :id, nor with :_links unless you pass in {no_links: 1} into the options as such

```ruby
options[:no_links] = params[:no_links] unless params[:no_links].blank?
```

### Using helper methods

You can mix-in code from another ruby module into your serializer class to reuse functions across your app.

Since a serializer is evaluated in a the context of a `class` rather than an `instance` of a class, you need to make sure that your methods act as `class` methods when mixed in.


##### Using ActiveSupport::Concern

``` ruby

module AvatarHelper
  extend ActiveSupport::Concern

  class_methods do
    def avatar_url(user)
      user.image.url
    end
  end
end

class UserSerializer
  include JSONAPI::Serializer

  include AvatarHelper # mixes in your helper method as class method

  set_type :user

  attributes :name, :email

  attribute :avatar do |user|
    avatar_url(user)
  end
end

```

##### Using Plain Old Ruby

``` ruby
module AvatarHelper
  def avatar_url(user)
    user.image.url
  end
end

class UserSerializer
  include JSONAPI::Serializer

  extend AvatarHelper # mixes in your helper method as class method

  set_type :user

  attributes :name, :email

  attribute :avatar do |user|
    avatar_url(user)
  end
end

```

### Customizable Options

Option | Purpose | Example
------------ | ------------- | -------------
set_type | Type name of Object and required if you define a different serializer class | `set_type :movie`
set_system_type | Passes system to :self and all other links which do not have them provided | `set_system_type :user_service`
key | Key of Object.  This is a far more performant way to change the json key than if providing a name a block to retrieve the object. | fast: `belongs_to :owner, key: :user`  slower: `belongs_to :user { |obj| obj.owner }`
set_id | ID of Object | `set_id :owner_id` or `set_id { \|record, params\| params[:admin] ? record.id : "#{record.name.downcase}-#{record.id}" }`
cache_options | Hash with store to enable caching and optional further cache options | `cache_options store: ActiveSupport::Cache::MemoryStore.new, expires_in: 5.minutes`
id_method_name | Set custom method name to get ID of an object (If block is provided for the relationship, `id_method_name` is invoked on the return value of the block instead of the resource object) | `has_many :locations, id_method_name: :place_ids`
object_method_name | Set custom method name to get related objects | `has_many :locations, object_method_name: :places`
record_type | Set custom Object Type for a relationship | `belongs_to :owner, record_type: :user`
serializer | Set custom Serializer for a relationship | `has_many :actors, serializer: :custom_actor`, `has_many :actors, serializer: MyApp::Api::V1::ActorSerializer`, or `has_many :actors, serializer -> (object, params) { (return a serializer class) }`
polymorphic | Allows different record types for a polymorphic association | `has_many :targets, polymorphic: true`

### Performance Instrumentation

Performance instrumentation is available by using the
`active_support/notifications`.

To enable it, include the module in your serializer class:

```ruby
require 'jsonapi/serializer'
require 'jsonapi/serializer/instrumentation'

class MovieSerializer
  include JSONAPI::Serializer
  include JSONAPI::Serializer::Instrumentation

  # ...
end
```

[Skylight](https://www.skylight.io/) integration is also available and
supported by us, follow the Skylight documentation to enable it.

### Running Tests
The project has and requires unit tests, functional tests and performance
tests. To run tests use the following command:

```bash
rspec
```

## Contributing

Please follow the instructions we provide as part of the issue and
pull request creation processes.

This project is intended to be a safe, welcoming space for collaboration, and
contributors are expected to adhere to the
[Contributor Covenant](https://contributor-covenant.org) code of conduct.
