require 'spec_helper'

RSpec.describe JSONAPI::Serializer do
  let(:actor) { Actor.fake }
  let(:params) { {} }

  describe 'with errors' do
    it do
      expect do
        BadMovieSerializerActorSerializer.new(
          actor
        )
      end.to_not raise_error(
        NameError, /cannot resolve a serializer class for 'bad'/
      )
    end

  end
end
