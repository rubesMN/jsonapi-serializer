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
    it 'works' do
      expect(serialized['_links'].map {|lnk| lnk['rel']}).to include('self')
      expect(serialized['_links'].map {|lnk| lnk['href']}).to match_array(["Rails.application.routes.url_helpers.url_for([obj, only_path: true])", movie.url])
      expect(serialized['actors'].reduce([]) do |array, actr|
         array.concat(actr['_links'].map{|lnk| lnk['rel']})
      end).to match_array(['self', 'bio', 'hair_salon_discount'])
      expect(serialized['actors'].reduce([]) do |array, actr|
             array.concat(actr['_links'].map{|lnk| lnk['href']})
      end).to match_array(["Rails.application.routes.url_helpers.url_for([obj, only_path: true])",
                                "https://www.imdb.com/name/nm0000098/",
                                "www.somesalon.com/#{movie.actors.first.uid}"])
    end

  end
end
