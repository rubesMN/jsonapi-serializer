require 'spec_helper'

RSpec.describe JSONAPI::Serializer do
  let(:actor) do
    act = Actor.fake
    act.movies = [Movie.fake]
    act
  end
  let(:params) { {} }
  let(:serialized) do
    ActorSerializer.new(actor, params).serializable_hash.as_json
  end

  describe 'attributes' do
    it do
      expect(serialized).to have_id(actor.uid)

      expect(serialized)
        .to have_jsonapi_attributes('first_name', 'last_name', 'email').exactly
      expect(serialized).to have_attribute('first_name')
        .with_value(actor.first_name)
      expect(serialized).to have_attribute('last_name')
        .with_value(actor.last_name)
      expect(serialized).to have_attribute('email')
        .with_value(actor.email)
    end

    context 'with nil identifier' do
      before { actor.uid = nil }

      it { expect(serialized).to have_id(nil) }
    end

    context 'with `if` conditions' do
      let(:params) { { params: { conditionals_off: 'yes' } } }

      it do
        expect(serialized).not_to have_attribute('email')
      end
    end

    context 'with new compound fields concept' do
      let(:params) do
        {
          fields: [ :first_name, {played_movies: [:release_year]} ]
        }
      end

      it do
        expect(serialized)
          .to have_jsonapi_attributes(:first_name).exactly

        expect(serialized['played_movies']).to include(
                                                 have_id(actor.movies[0].id)
                                                 .and(have_jsonapi_attributes('release_year').exactly)
                                               )

      end
    end
  end
end
