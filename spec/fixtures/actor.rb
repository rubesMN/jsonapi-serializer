require 'active_support/cache'
require 'jsonapi/serializer/instrumentation'

class Actor < User
  attr_accessor :movies, :movie_ids

  def self.fake(id = nil)
    faked = super(id)
    faked.movies = []
    faked.movie_ids = []
    faked
  end

  def movie_urls
    {
      movie_url: movies[0]&.url
    }
  end
  def bio_link
    "https://www.imdb.com/name/nm0000098/"
  end
  def favorite_movie
    movies.present? ? movies[0] : nil
  end
  def favorite_movie_id
    movies.present? ? movies[0]&.id : nil
  end
end

class ActorSerializer < UserSerializer
  set_type :actor

  attribute :email, if: ->(_object, params) { params[:conditionals_off].nil? }

  has_many(
    :played_movies,
    serializer: :movie,
    if: ->(_object, params) { params[:conditionals_off].nil? }
  ) do |object|
    object.movies
  end

  has_one :favorite_movie,
          serializer: :movie

  link rel: :bio, system: :IMDB, link_method_name: :bio_link
  link rel: :hair_salon_discount do |obj|
    "www.somesalon.com/#{obj.uid}"
  end
end

class CamelCaseActorSerializer
  include JSONAPI::Serializer

  set_key_transform :camel

  set_id :uid
  set_type :user_actor
  attributes :first_name

  link rel: :movie_url do |obj|
    obj.movie_urls.values[0]
  end

  has_many(
    :played_movies,
    serializer: :movie
  ) do |object|
    object.movies
  end
end

class BadMovieSerializerActorSerializer < ActorSerializer
  has_many :played_movies, serializer: :bad, object_method_name: :movies
end

module Cached
  class ActorSerializer < ::ActorSerializer
    # TODO: Fix this, the serializer gets cached on inherited classes...
    has_many :played_movies, serializer: :movie do |object|
      # this ill-advised block gets the actual movies array itself and you could make mistakes obviously
      # Its better to use relationship_name of :movies and identify the key as :played_movies and avoid this block
      object.movies
    end

    cache_options(
      store: ActiveSupport::Cache::MemoryStore.new,
      namespace: 'test'
    )
  end
end

module Instrumented
  class ActorSerializer < ::ActorSerializer
    include ::JSONAPI::Serializer::Instrumentation
  end
end
