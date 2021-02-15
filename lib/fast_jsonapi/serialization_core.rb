# frozen_string_literal: true

require 'active_support/concern'
require 'digest/sha1'

module FastJsonapi
  MandatoryField = Class.new(StandardError)

  module SerializationCore
    extend ActiveSupport::Concern

    included do
      class << self
        attr_accessor :attributes_to_serialize,
                      :relationships_to_serialize,
                      :transform_method,
                      :record_type,
                      :system_type,
                      :api_namespace,
                      :record_id,
                      :cache_store_instance,
                      :cache_store_options,
                      :data_links
      end
    end

    class_methods do

      def links_hash(record, original_options, params = {})
        data_links.each_with_object([]) do |link, array|
          link.serialize(record, params, array) if original_options[:no_auto_links].blank? || !link.no_link_if_err
        end
      end

      def attributes_hash(record, fieldset = nil, params = {})
        attributes = attributes_to_serialize
        attributes = attributes.slice(*fieldset) if fieldset.present?
        attributes = {} if fieldset == []

        attributes.each_with_object({}) do |(_k, attribute), hash|
          attribute.serialize(record, params, hash)
        end
      end

      def relationships_hash(record, fieldset = nil, original_options = {}, params = {})
        relationships = relationships_to_serialize
        relationships = trim_relationships_given_fieldset(relationships, fieldset)

        relationships.each_with_object({}) do |(key, relationship), hash|
          relationship.serialize(record, original_options, params, hash, fieldset)
        end
      end

      # filter out based on either the relationship name, or the key if the user provided one
      def trim_relationships_given_fieldset(relationships, fieldset)
        return relationships if fieldset.nil? # making this super clear,.. if nothing sent in, emit everything
        return {} if fieldset == [] # empty array fieldset means emit nothing
        expanded_fieldset = fieldset.each_with_object([]) {|f,array| f.is_a?(Hash) ? array.concat(f.keys) : array << f}
        relationships.each_with_object({}) do |(key, relationship), hash|
          hash[key] = relationship if expanded_fieldset.include?(relationship.get_json_field_name)
        end
      end

      def record_hash(record, fieldset, original_options, params = {})
        if cache_store_instance
          cache_opts = record_cache_options(cache_store_options, fieldset, params)
          record_hash = cache_store_instance.fetch(record_cache_key(record, params), **cache_opts) do
            temp_hash = { id: id_from_record(record, params) }
            temp_hash.merge!(attributes_hash(record, fieldset, params)) if attributes_to_serialize.present?
            temp_hash.merge!(relationships_hash(record, fieldset, original_options, params)) if relationships_to_serialize.present?
            temp_hash[:_links] = links_hash(record, original_options, params) if data_links.present? && original_options[:no_links].blank?
            temp_hash
          end
        else
          record_hash = { id: id_from_record(record, params) }
          record_hash.merge!(attributes_hash(record, fieldset, params)) if attributes_to_serialize.present?
          record_hash.merge!(relationships_hash(record, fieldset, original_options, params)) if relationships_to_serialize.present?
          record_hash[:_links] = links_hash(record, original_options, params) if data_links.present? && original_options[:no_links].blank?
        end

        record_hash
      end

      def record_cache_key(record, params)
        "#{self.name}:#{id_from_record(record, params)}"
      end

      # Cache options helper. Use it to adapt cache keys/rules.
      #
      # If a fieldset is specified, it modifies the namespace to include the
      # fields from the fieldset.
      #
      # @param options [Hash] default cache options
      # @param fieldset [Array, nil] passed fieldset values
      # @param params [Hash] the serializer params
      #
      # @return [Hash] processed options hash
      # rubocop:disable Lint/UnusedMethodArgument
      def record_cache_options(options, fieldset, params)
        return options unless fieldset

        options = options ? options.dup : {}
        options[:namespace] ||= 'jsonapi-serializer'

        fieldset_key = fieldset.empty? ? '' : fieldset.to_s

        # Use a fixed-length fieldset key if the current length is more than
        # the length of a SHA1 digest
        if fieldset_key.length > 40
          fieldset_key = Digest::SHA1.hexdigest(fieldset_key)
        end

        options[:namespace] = "#{options[:namespace]}-fieldset:#{fieldset_key}"
        options
      end
      # rubocop:enable Lint/UnusedMethodArgument

      def id_from_record(record, params)
        return FastJsonapi.call_proc(record_id, record, params) if record_id.is_a?(Proc)
        return record.send(record_id) if record_id
        raise MandatoryField, 'id is a mandatory field in the jsonapi spec' unless record.respond_to?(:id)

        record.id
      end

    end
  end
end
