class Movie
  attr_accessor(
    :id,
    :name,
    :year,
    :actor_or_user,
    :actors,
    :actor_ids,
    :polymorphics,
    :owner,
    :owner_id
  )

  def self.fake(id = nil)
    faked = new
    faked.id = id || SecureRandom.uuid
    faked.name = FFaker::Movie.title
    faked.year = FFaker::Vehicle.year
    faked.actors = []
    faked.actor_ids = []
    faked.polymorphics = []
    faked
  end

  def url(obj = nil)
    @url ||= FFaker::Internet.http_url
    return @url if obj.nil?

    @url + '?' + obj.hash.to_s
  end

  def owner=(ownr)
    @owner = ownr
    @owner_id = ownr.uid
  end

  def actors=(acts)
    @actors = acts
    @actor_ids = actors.map do |actor|
      actor.movies << self
      actor.uid
    end
  end
end

class MovieSerializer
  include JSONAPI::Serializer

  set_type :movie

  attributes :name
  attribute :release_year do |object|
    object.year
  end

  link rel: :self, link_method_name: :url

  belongs_to :owner, serializer: UserSerializer

  belongs_to :actor_or_user,
             id_method_name: :uid,
             polymorphic: true
  has_many(
    :actors
  )
  has_one(
    :creator,
    object_method_name: :owner,
    id_method_name: :uid,
    serializer: ->(object, _params) { UserSerializer if object.is_a?(User) }
  )
  has_many(
    :actors_and_users,
    id_method_name: :uid,
    polymorphic: true
  ) do |obj|
    obj.polymorphics
  end

  has_many(
    :non_polymorphic_actors_and_users,
    id_method_name: :uid
  ) do |obj|
    obj.polymorphics
  end
end

module Cached
  class MovieSerializer < ::MovieSerializer
    cache_options(
      store: ActorSerializer.cache_store_instance,
      namespace: 'test'
    )

    has_one(
      :creator,
      id_method_name: :uid,
      serializer: :user
    ) do |obj|
      obj.owner
    end
  end
end


module Selfless
  class MovieSerializer < ::MovieSerializer
    link rel: :self, system: :SomeSystem do |obj|
      "some overridden self link"
    end
  end
end

module SpecialSelf
  class MovieThrowSerializer < ::MovieSerializer
    link rel: :self, link_method_name: :some_bad_method
  end
  class MovieNoThrowSerializer
    include JSONAPI::Serializer
    link rel: :self, no_link_if_err: true, link_method_name: :some_bad_method
    attribute :name
  end
end

module Linkless
  class MovieSerializer
    include JSONAPI::Serializer

    set_type :movie
    attributes :name
    attribute :release_year do |object|
      object.year
    end
  end

end
