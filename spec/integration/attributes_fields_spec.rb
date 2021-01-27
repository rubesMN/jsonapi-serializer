require 'spec_helper'

RSpec.describe JSONAPI::Serializer do
  let(:actor) do
    act = Actor.fake
    act.movies = [Movie.fake]
    act
  end
  let(:params) { {} }
  let(:serialized) do
    ActorSerializer.new(actor, params).serializable_hash
  end

  describe 'attributes' do
    it do
      expect(serialized[:id]).to eq(actor.uid)

      expect(serialized.keys).to match_array([:first_name, :last_name, :email, :id, :played_movies, :favorite_movie, :_links])
      expect(serialized[:first_name]).to eq(actor.first_name)
      expect(serialized[:last_name]).to eq(actor.last_name)
      expect(serialized[:email]).to eq(actor.email)

    end

    context 'with nil identifier' do
      before { actor.uid = nil }

      it { expect(serialized[:id]).to eq(nil) }
    end

    context 'with `if` conditions' do
      let(:params) { { params: { conditionals_off: 'yes' } } }

      it do
        expect(serialized[:email]).to be_nil
      end
    end

    context 'with new compound fields concept' do
      let(:params) do
        {
          fields: [ :first_name, {played_movies: [:release_year]} ]
        }
      end

      it do
        expect(serialized.keys)
          .to match_array([:first_name, :played_movies, :id, :_links])
        expect(serialized[:first_name]).to eq(actor.first_name)

        expect(serialized[:played_movies][0].keys).to match_array([:id, :release_year, :_links])

        expect(serialized[:played_movies].size).to be(1)
        expect(serialized[:played_movies][0][:release_year]).to eq(actor.movies[0].year)

      end
    end
  end
end
