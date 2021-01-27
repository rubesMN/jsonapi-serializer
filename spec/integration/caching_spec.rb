require 'spec_helper'

RSpec.describe JSONAPI::Serializer do
  let(:actor) do
    faked = Actor.fake
    movie = Movie.fake
    movie.owner = User.fake
    movie.actors = [faked]
    faked.movies = [movie]
    faked
  end
  let(:cache_store_actor) { Cached::ActorSerializer.cache_store_instance }
  let(:cache_store_movie) { Cached::MovieSerializer.cache_store_instance }
  let(:cache_store_user) { Cached::UserSerializer.cache_store_instance }

  describe 'with caching' do
    it do
      expect(cache_store_actor.delete(actor, namespace: 'test')).to be(false)

      result = Cached::ActorSerializer.new(
        [actor, actor] # turn into fields, include: ['played_movies', 'played_movies.owner']
      ).serializable_hash

      gen_cache_options = Cached::ActorSerializer.record_cache_options({namespace: 'test'}, nil, {})
      key_actor = Cached::ActorSerializer.record_cache_key(actor, {})
      expect(cache_store_actor.exist?(key_actor, gen_cache_options)).to  be(true)
      expect(cache_store_actor.delete(key_actor, gen_cache_options)).to be(true)

      key_movie = Cached::MovieSerializer.record_cache_key(actor.movies[0], {})
      expect(cache_store_movie.delete(key_movie, gen_cache_options)).to be(true)
      expect(
        cache_store_movie.delete(key_movie, gen_cache_options)
      ).to be(false)

      key_user = Cached::UserSerializer.record_cache_key(actor.movies[0].owner, {})
      expect(cache_store_user.delete(key_user, gen_cache_options)).to be(true)
      expect(
        cache_store_user.delete(key_user, gen_cache_options)
      ).to be(false)
    end

  end

  describe 'with caching and different fieldsets' do
    context 'when fieldset is provided' do
      it 'includes the fieldset in the namespace' do
        expect(cache_store_actor.delete(actor, namespace: 'test')).to be(false)

        Cached::ActorSerializer.new(
          [actor], fields: [:first_name]
        ).serializable_hash

        # Expect cached keys to match the passed fieldset
        gen_cache_options_w_fields = Cached::ActorSerializer.record_cache_options({namespace: 'test'}, [:first_name], {})
        key_actor = Cached::ActorSerializer.record_cache_key(actor, {})
        expect(cache_store_actor.read(key_actor, gen_cache_options_w_fields).keys).to eq(%i[id first_name _links])

        Cached::ActorSerializer.new(
          [actor]
        ).serializable_hash

        # Expect cached keys to match all valid actor fields (no fieldset)
        gen_cache_options_NO_fields = Cached::ActorSerializer.record_cache_options({namespace: 'test'}, nil, {})
        expect(cache_store_actor.read(key_actor, gen_cache_options_NO_fields).keys).to eq(%i[id first_name last_name email played_movies favorite_movie _links])
        expect(cache_store_actor.delete(key_actor, gen_cache_options_NO_fields)).to be(true)

        expect(cache_store_actor.delete(key_actor, gen_cache_options_w_fields)).to be(true)
      end
    end

    context 'when long fieldset is provided invoking SHA1 digest' do
      let(:actor_keys) { %i[first_name last_name email played_movies more_fields yet_more_fields so_very_many_fields] }
      let(:digest_key) { Digest::SHA1.hexdigest(actor_keys.join('_')) }

      it 'includes the hashed fieldset in the namespace' do
        Cached::ActorSerializer.new(
          [actor], fields: actor_keys
        ).serializable_hash

        key_actor = Cached::ActorSerializer.record_cache_key(actor, {})
        gen_cache_options = Cached::ActorSerializer.record_cache_options({namespace: 'test'}, actor_keys, {})
        expect(cache_store_actor.read(key_actor, gen_cache_options).keys).to eq(
                                                                               %i[id first_name last_name email played_movies _links]
        )

        expect(cache_store_actor.delete(key_actor, gen_cache_options)).to be(true)
      end
    end

    context 'when nested fieldset is provided' do
      let(:actor_keys) { [:first_name, :last_name, {played_movies: [:release_year]} ] }

      it 'includes the hashed fieldset in the namespace properly' do
        Cached::ActorSerializer.new(
          [actor], fields: actor_keys
        ).serializable_hash

        key_actor = Cached::ActorSerializer.record_cache_key(actor, {})
        gen_cache_options = Cached::ActorSerializer.record_cache_options({namespace: 'test'}, actor_keys, {})
        expect(cache_store_actor.read(key_actor, gen_cache_options).keys).to eq(
                                                                               %i[id first_name last_name played_movies _links]
                                                                             )
        expect(cache_store_actor.read(key_actor, gen_cache_options)[:played_movies].size).to eq(1)

        expect(cache_store_actor.read(key_actor, gen_cache_options)[:played_movies].first).to include(:id, :release_year, :_links)
        expect(cache_store_actor.read(key_actor, gen_cache_options)[:played_movies].first).to_not include(:creator, :name)
        expect(cache_store_actor.delete(key_actor, gen_cache_options)).to be(true)
      end
    end
  end
end
