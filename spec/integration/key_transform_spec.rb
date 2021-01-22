require 'spec_helper'

RSpec.describe JSONAPI::Serializer do
  let(:actor) { Actor.fake }
  let(:params) { {} }
  let(:serialized) do
    CamelCaseActorSerializer.new(actor, params).serializable_hash.as_json
  end

  describe 'camel case key tranformation' do
    it do
      expect(serialized['id']).to eq(actor.uid)
      expect(serialized.keys).to include('FirstName', 'PlayedMovies')

      expect(serialized['_links'].map {|lnk| lnk['rel']}).to match_array(['self', 'MovieUrl'])
    end
  end
end
