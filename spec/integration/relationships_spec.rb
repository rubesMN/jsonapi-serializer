require 'spec_helper'

RSpec.describe JSONAPI::Serializer do
  let(:movie) do
    mov = Movie.fake
    mov.actors = rand(2..5).times.map { Actor.fake }
    mov.owner = User.fake
    poly_act = Actor.fake
    poly_act.movies = [Movie.fake]
    mov.polymorphics = [User.fake, poly_act]
    mov.actor_or_user = Actor.fake
    mov
  end
  let(:params) { {} }
  let(:serialized) do
    MovieSerializer.new(movie, params).serializable_hash.as_json
  end

  describe 'relationships' do
    it do
      a=serialized
      expect(serialized.keys).to eq(%w[id name release_year owner actor_or_user actors creator actors_and_users non_polymorphic_actors_and_users _links])

      expect(serialized['actors'].size).to be_between(2,5)
      expect(serialized['actors'][0].keys).to match_array(%w[id first_name last_name email played_movies favorite_movie _links])

      # prove we nest level 1 deep
      expect(serialized['actors'][0].each_with_object([]) do |(k, v), arry|
        arry << v unless k=='played_movies' || k=='_links' || k=='favorite_movie'
      end).to match_array([movie.actors[0].uid, movie.actors[0].first_name, movie.actors[0].last_name, movie.actors[0].email])

      # prove we nest level 2 deep
      expect(serialized['actors'][0]['played_movies'][0].each_with_object([]) do |(k, v), arry|
        arry << v if !v.nil? && v.is_a?(String)
      end).to match_array([movie.actors[0].movies[0].id, movie.actors[0].movies[0].name, movie.actors[0].movies[0].year])

      # prove we nest level 3 deep with belongs_to
      expect(serialized['actors'][0]['played_movies'][0]['owner'].each_with_object([]) do |(k, v), arry|
        arry << v if !v.nil? && v.is_a?(String)
      end).to match_array([movie.actors[0].movies[0].owner.uid,
                           movie.actors[0].movies[0].owner.first_name,
                           movie.actors[0].movies[0].owner.last_name,
                           movie.actors[0].movies[0].owner.email
                          ])

      # prove we nest level 3 deep with has_many
      expect(serialized['actors'][0]['played_movies'][0]['actors'][0].each_with_object([]) do |(k, v), arry|
        arry << v if !v.nil? && v.is_a?(String)
      end).to match_array([movie.actors[0].movies[0].actors[0].uid,
                           movie.actors[0].movies[0].actors[0].first_name,
                           movie.actors[0].movies[0].actors[0].last_name,
                           movie.actors[0].movies[0].actors[0].email
                          ])

      # prove we nest level 4 deep with :has_many but only id, _links
      expect(serialized['actors'][0]['played_movies'][0]['actors'][0]['played_movies'][0].each_with_object([]) do |(k, v), arry|
        arry << k
      end).to match_array(['id','_links'])
      expect(serialized['actors'][0]['played_movies'][0]['actors'][0]['played_movies'][0].each_with_object([]) do |(k, v), arry|
        arry << v if !v.nil? && v.is_a?(String)
      end).to match_array([movie.actors[0].movies[0].actors[0].movies[0].id])

      # prove we nest level 4 deep with :has_one but only id, _links
      expect(serialized['actors'][0]['played_movies'][0]['actors'][0]['favorite_movie'].each_with_object([]) do |(k, v), arry|
        arry << k
      end).to match_array(['id','_links'])
      expect(serialized['actors'][0]['played_movies'][0]['actors'][0]['favorite_movie'].each_with_object([]) do |(k, v), arry|
        arry << v if !v.nil? && v.is_a?(String)
      end).to match_array([movie.actors[0].movies[0].actors[0].favorite_movie.id])

      # belongs_to test to ensure defined serializer works
      expect(serialized['owner'].keys).to match_array(%w(id first_name last_name email _links))
      expect(serialized['owner']['id']).to eq(movie.owner.uid)
      expect(serialized['owner']['first_name']).to eq(movie.owner.first_name)

      # prove all is ok with using object_method_name and dynamic serializer
      expect(serialized['creator'].keys).to match_array(%w(id first_name last_name email _links))
      expect(serialized['creator']['id']).to eq(movie.owner.uid)
      expect(serialized['creator']['first_name']).to eq(movie.owner.first_name)

      # belongs_to with id_method_name defined and something with polymorphic
      # polymorphic emits id, type, _links with self only
      expect(serialized['actor_or_user'].keys).to match_array(%w(id type _links))
      expect(serialized['actor_or_user']['id']).to eq(movie.actor_or_user.uid)
      expect(serialized['actor_or_user']['type']).to eq("Actor")

      # has_many polymorphic
      expect(serialized['actors_and_users'][0].keys).to match_array(%w(id type _links))
      expect(serialized['actors_and_users'][0]['id']).to eq(movie.polymorphics.first.uid)
      expect(serialized['actors_and_users'][0]['type']).to eq("User")

      expect(serialized['actors_and_users'][1].keys).to match_array(%w(id type _links))
      expect(serialized['actors_and_users'][1]['id']).to eq(movie.polymorphics.last.uid)
      expect(serialized['actors_and_users'][1]['type']).to eq("Actor")

      # has_many with no polymorphic and no serializer and no type.. simply output id, _link
      expect(serialized['non_polymorphic_actors_and_users'][0].keys).to match_array(%w(id _links))
      expect(serialized['non_polymorphic_actors_and_users'][0]['id']).to eq(movie.polymorphics.first.uid)
      expect(serialized['non_polymorphic_actors_and_users'][1].keys).to match_array(%w(id _links))
      expect(serialized['non_polymorphic_actors_and_users'][1]['id']).to eq(movie.polymorphics.last.uid)

    end

    context 'with compound include' do
      let(:fields) do
        [:name,
        {owner: [:first_name, :last_name]},
        :release_year,
        {creator: [:first_name, :last_name]},
        {actors: [:first_name,
                   :email,
                   {played_movies: [:name,
                                    :release_year,
                                    {creator: [:email]},
                                    {actors: [:email]}]},
                   {favorite_movie: [:name]}]}
        ]
      end
      context 'with links' do
        let(:params) do
          { fields: fields }
        end
        it do
          expect(serialized.keys).to match_array(%w(id name owner release_year creator actors _links))

          expect(serialized['owner'].keys).to match_array(%w[id first_name last_name _links])
          expect(serialized['creator'].keys).to match_array(%w[id first_name last_name _links])

          expect(serialized['actors'].size).to be_between(2,5)
          expect(serialized['actors'][0].keys).to match_array(%w[id first_name email played_movies favorite_movie _links])
          expect(serialized['actors'][0]['played_movies'][0].keys).to match_array(%w[id name release_year creator actors _links])
          expect(serialized['actors'][0]['played_movies'][0]['creator'].keys).to match_array(%w[id email _links])
          expect(serialized['actors'][0]['played_movies'][0]['actors'][0].keys).to match_array(%w[id email _links])
          expect(serialized['actors'][0]['favorite_movie'].keys).to match_array(%w[id name _links])
        end
      end

      context 'without links' do
        let(:params) do
          { fields: fields, no_links: 1 }
        end
        it do
          expect(serialized.keys).to match_array(%w(id name owner release_year creator actors))

          expect(serialized['owner'].keys).to match_array(%w[id first_name last_name])
          expect(serialized['creator'].keys).to match_array(%w[id first_name last_name])

          expect(serialized['actors'].size).to be_between(2,5)
          expect(serialized['actors'][0].keys).to match_array(%w[id first_name email played_movies favorite_movie ])
          expect(serialized['actors'][0]['played_movies'][0].keys).to match_array(%w[id name release_year creator actors ])
          expect(serialized['actors'][0]['played_movies'][0]['creator'].keys).to match_array(%w[id email ])
          expect(serialized['actors'][0]['played_movies'][0]['actors'][0].keys).to match_array(%w[id email ])
          expect(serialized['actors'][0]['favorite_movie'].keys).to match_array(%w[id name ])
        end
      end

    end

    context 'with `if` conditions' do
      let(:params) do
        {
          fields: [:actors],
          params: { conditionals_off: 'yes' }
        }
      end

      it do
        expect(serialized.keys).to match_array(%w(id actors _links))

        expect(serialized['actors'].size).to be_between(2,5)
        expect(serialized['actors'][0].keys).to match_array(%w[id first_name last_name favorite_movie _links])
        expect(serialized['actors'][1].keys).to match_array(%w[id first_name last_name favorite_movie _links])

      end
    end

  end
end
