require 'spec_helper'

RSpec.describe JSONAPI::Serializer do
  let(:movie) do
    faked = Movie.fake
    faked.actors = [Actor.fake]
    faked
  end
  let(:params) { {} }
  let(:serialized) do
    MovieSerializer.new(movie, params).serializable_hash.as_json
  end

  describe 'links' do
    context 'standard' do
      it 'works' do
        expect(serialized['_links'].map {|lnk| lnk['rel']}).to include('self')
        expect(serialized['_links'].map {|lnk| lnk['href']}).to match_array([movie.url])
        expect(serialized['actors'].reduce([]) do |array, actr|
           array.concat(actr['_links'].map{|lnk| lnk['rel']})
        end).to match_array(['self', 'bio', 'hair_salon_discount'])
        expect(serialized['actors'].reduce([]) do |array, actr|
               array.concat(actr['_links'].map{|lnk| lnk['href']})
        end).to match_array(["unresolvable",
                                  "https://www.imdb.com/name/nm0000098/",
                                  "www.somesalon.com/#{movie.actors.first.uid}"])
      end
    end

    context 'self exception behavior' do
      let (:serialized2) do
        SpecialSelf::MovieThrowSerializer.new(movie, params).serializable_hash.as_json
      end
      let (:serialized3) do
        SpecialSelf::MovieNoThrowSerializer.new(movie, params).serializable_hash.as_json
      end
      it 'throws exception' do
        expect { serialized2 }.to raise_error(NoMethodError)
      end
      it 'silently gives no link' do
        expect(serialized3['_links'].size).to be(0)
      end
    end

    context 'no_links set' do
      let (:serialized3) do
        MovieSerializer.new(movie, {no_links: 1}).serializable_hash.as_json
      end
      context 'propigates no_links' do
        it 'links are gone' do
          expect(serialized3['_links']).to be_nil
          expect(serialized3['actors'][0]['_links']).to be_nil
        end
      end

      context 'links still stay when polymorphic set' do
        let(:movie4) do
          faked = Movie.fake
          faked.actors = [Actor.fake]
          faked.polymorphics = [User.fake, Actor.fake]
          faked.actor_or_user = Actor.fake
          faked
        end
        let(:serialized4) do
          MovieSerializer.new(movie4, {no_links: 1}).serializable_hash.as_json
        end
        it 'adds type and keeps links when polymorphic set' do
          expect(serialized4['actor_or_user'].keys).to match_array(%w(id type _links))
          expect(serialized4['actor_or_user']['id']).to eq(movie4.actor_or_user.uid)
          expect(serialized4['actor_or_user']['type']).to eq("Actor")
          expect(serialized4['actor_or_user']['_links'].first['href']).to eq("unresolvable") # would have resolved if via ActiveSupport

          expect(serialized4['actors_and_users'][0].keys).to match_array(%w(id type _links))
          expect(serialized4['actors_and_users'][0]['id']).to eq(movie4.polymorphics.first.uid)
          expect(serialized4['actors_and_users'][0]['type']).to eq("User")
          expect(serialized4['actors_and_users'][0]['_links'].first['href']).to eq("unresolvable") # would have resolved if via ActiveSupport

          expect(serialized4['actors_and_users'][1].keys).to match_array(%w(id type _links))
          expect(serialized4['actors_and_users'][1]['id']).to eq(movie4.polymorphics.last.uid)
          expect(serialized4['actors_and_users'][1]['type']).to eq("Actor")
          expect(serialized4['actors_and_users'][1]['_links'].first['href']).to eq("unresolvable") # would have resolved if via ActiveSupport

          expect(serialized4['non_polymorphic_actors_and_users'][0].keys).to match_array(%w(id))
          expect(serialized4['non_polymorphic_actors_and_users'][0]['id']).to eq(movie4.polymorphics.first.uid)
          expect(serialized4['non_polymorphic_actors_and_users'][1].keys).to match_array(%w(id))
          expect(serialized4['non_polymorphic_actors_and_users'][1]['id']).to eq(movie4.polymorphics.last.uid)
        end
      end
    end
  end
end
