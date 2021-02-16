# frozen_string_literal: true

require 'active_support/time'
require 'active_support/concern'
require 'active_support/inflector'
require 'active_support/core_ext/numeric/time'
require 'fast_jsonapi/helpers'
require 'fast_jsonapi/attribute'
require 'fast_jsonapi/relationship'
require 'fast_jsonapi/link'
require 'fast_jsonapi/serialization_core'
require 'fast_jsonapi/constants'

module FastJsonapi
  module ObjectSerializer
    extend ActiveSupport::Concern
    include SerializationCore
    include Constants

    TRANSFORMS_MAPPING = {
      camel: :camelize,
      camel_lower: [:camelize, :lower],
      dash: :dasherize,
      underscore: :underscore
    }.freeze

    included do
      # Set record_type based on the name of the serializer class
      set_type(reflected_record_type) if reflected_record_type
      add_self_link
    end

    def initialize(resource, options = {})
      process_options(options)
      @resource = resource
    end

    def serializable_hash
      if self.class.is_collection?(@resource, @is_collection)
        return hash_for_collection
      end

      hash_for_one_record
    end
    alias to_hash serializable_hash

    def hash_for_one_record
      serializable_hash = {  }

      if @resource
        serializable_hash = self.class.record_hash(@resource, @fieldsets, @options, @params)
      end

      serializable_hash
    end

    def hash_for_collection
      data = []
      @resource.each do |record|
        data << self.class.record_hash(record, @fieldsets, @options, @params)
      end

      serializable_hash = data
      serializable_hash
    end

    private

    def process_options(options)
      @fieldsets = deep_symbolize(options&.dig(:fields))
      @params = {}

      if options.blank? || options.empty?
        @options = {}
        @options[:nest_level] = 1
        @params = {}
      else
        @options = options
        if @options[:nest_level]
          @options[:nest_level] += 1
        else
          @options[:nest_level] = 1
        end
        @params = options[:params] || {}
        raise ArgumentError, '`params`  passed within options to serializer must be a hash' unless @params.is_a?(Hash)
      end

      @is_collection = @options[:is_collection]
      @params[:system_type] = self.class.system_type if self.class.system_type.present?
    end

    def deep_symbolize(collection)
      return nil unless collection
      if collection.is_a? Hash
        collection.each_with_object({}) do |(k, v), hsh|
          hsh[k.to_sym] = deep_symbolize(v)
        end
      elsif collection.is_a? Array
        collection.map { |i| deep_symbolize(i) }
      else
        collection.to_sym
      end
    end

    class_methods do
      # Detects a collection/enumerable
      #
      # @return [TrueClass] on a successful detection
      def is_collection?(resource, force_is_collection = nil)
        return force_is_collection unless force_is_collection.nil?

        resource.is_a?(Enumerable) && !resource.respond_to?(:each_pair)
      end

      def inherited(subclass)
        super(subclass)
        subclass.attributes_to_serialize = attributes_to_serialize.dup if attributes_to_serialize.present?
        subclass.relationships_to_serialize = relationships_to_serialize.dup if relationships_to_serialize.present?
        subclass.transform_method = transform_method
        subclass.data_links = data_links.dup if data_links.present?
        subclass.cache_store_instance = cache_store_instance
        subclass.cache_store_options = cache_store_options
        subclass.set_type(subclass.reflected_record_type) if subclass.reflected_record_type
        subclass.record_id = record_id
      end

      def reflected_record_type
        return @reflected_record_type if defined?(@reflected_record_type)

        @reflected_record_type ||= begin
          name.split('::').last.chomp('Serializer').underscore.gsub("JsonApi",'').to_sym if name&.end_with?('Serializer')
        end
      end

      def set_key_transform(transform_name)
        self.transform_method = TRANSFORMS_MAPPING[transform_name.to_sym]

        # ensure that the record type is correctly transformed
        if record_type
          set_type(record_type)
        # TODO: Remove dead code
        elsif reflected_record_type
          set_type(reflected_record_type)
        end
      end

      def run_key_transform(input)
        if transform_method.present?
          input.to_s.send(*@transform_method).to_sym
        else
          input.to_sym
        end
      end

      def use_hyphen
        warn('DEPRECATION WARNING: use_hyphen is deprecated and will be removed from fast_jsonapi 2.0 use (set_key_transform :dash) instead')
        set_key_transform :dash
      end

      def set_system_type(system_type_name)
        self.system_type = system_type_name
      end

      def set_api_namespace(*api_namespace)
        self.api_namespace = api_namespace
      end

      def add_self_link
        link rel: :self, no_link_if_err: true do |obj|
          "#{Rails.application.routes.url_helpers.url_for([*self.api_namespace, obj, only_path: true])}" # requires Rails 4.1.8+
        end
      end

      def set_type(type_name)
        self.record_type = run_key_transform(type_name)
      end

      def set_id(id_name = nil, &block)
        self.record_id = block || id_name
      end

      def cache_options(cache_options)
        self.cache_store_instance = cache_options[:store]
        self.cache_store_options = cache_options.except(:store)
      end

      def attributes(*attributes_list, &block)
        attributes_list = attributes_list.first if attributes_list.first.class.is_a?(Array)
        options = attributes_list.last.is_a?(Hash) ? attributes_list.pop : {}
        self.attributes_to_serialize = {} if attributes_to_serialize.nil?

        # to support calling `attribute` with a lambda, e.g `attribute :key, ->(object) { ... }`
        block = attributes_list.pop if attributes_list.last.is_a?(Proc)

        attributes_list.each do |attr_name|
          method_name = attr_name
          key = run_key_transform(method_name)
          attributes_to_serialize[key] = Attribute.new(
            key: key,
            method: block || method_name,
            options: options
          )
        end
      end

      alias_method :attribute, :attributes

      def add_relationship(relationship)
        self.relationships_to_serialize = {} if relationships_to_serialize.nil?

        relationships_to_serialize[relationship.name] = relationship
      end

      def has_many(relationship_name, options = {}, &block)
        relationship = create_relationship(relationship_name, :has_many, options, block)
        add_relationship(relationship)
      end

      def has_one(relationship_name, options = {}, &block)
        relationship = create_relationship(relationship_name, :has_one, options, block)
        add_relationship(relationship)
      end

      def belongs_to(relationship_name, options = {}, &block)
        relationship = create_relationship(relationship_name, :belongs_to, options, block)
        add_relationship(relationship)
      end

      def create_relationship(base_key, relationship_type, options, block)
        name = base_key.to_sym
        if relationship_type == :has_many
          base_serialization_key = base_key.to_s.singularize
          id_postfix = '_ids'
        else
          base_serialization_key = base_key
          id_postfix = '_id'
        end
        polymorphic = fetch_polymorphic_option(options)

        Relationship.new(
          owner: self,
          key: options[:key] || run_key_transform(base_key),
          name: name,
          id_method_name: options[:id_method_name] || :id,
          record_type: options[:record_type],
          object_method_name: options[:object_method_name] || name,
          object_block: block,
          serializer: options[:serializer],
          relationship_type: relationship_type,
          polymorphic: polymorphic,
          conditional_proc: options[:if],
          transform_method: @transform_method,
          api_namespace: options[:api_namespace]
        )
      end

      def compute_id_method_name(options, id_method_name_from_relationship, polymorphic, block)
        if block.present? || options[:serializer]&.is_a?(Proc) || polymorphic
          options[:id_method_name] || :id
        else
          options[:id_method_name] || id_method_name_from_relationship
        end
      end

      def serializer_for(name)
        namespace = self.name.gsub(/()?\w+Serializer$/, '')
        serializer_name = name.to_s.demodulize.classify + 'Serializer'
        serializer_class_name = namespace + serializer_name
        begin
          serializer_class_name.constantize
        rescue NameError
          raise NameError, "#{self.name} cannot resolve a serializer class for '#{name}'.  " \
                           "Attempted to find '#{serializer_class_name}'. " \
                           'Consider specifying the serializer directly through options[:serializer].'
        end
      end

      def fetch_polymorphic_option(options)
        option = options[:polymorphic]
        return false unless option.present?
        return option if option.respond_to? :keys

        {}
      end

      # def link(params, &block)
      # params: {}
      #   :rel - what to name the link.. ie the 'relationship' - required
      #   :system - the high level context typically identifying the service you are calling
      #   :link_method_name - will be called on the object to resolve the link href -> will result in :href in output
      #   :type - "GET" or "POST" or "PUT",.. ie http verb. Defaults to 'GET'
      def link(params, &block)
        self.data_links = [] if data_links.nil?
        raise ArgumentError, '`link` parameters must be a hash and must include :rel' unless params.is_a?(Hash) && params[:rel].present?

        already_has_self = data_links.find {|dl| dl.rel == :self}
        if params[:rel] == :self && already_has_self
          # ensure only one self.. replace with this one assuming user knows better
          dl_index = 0
          replaced = false
          while dl_index < data_links.size && !replaced
            if data_links[dl_index].rel == :self
              replaced = true
              data_links[dl_index] = Link.new({
                                                rel: run_key_transform(params[:rel]),
                                                system: params[:system].presence || '',
                                                link_method_name: params[:link_method_name].presence || block,
                                                type: params[:type].presence || "GET",
                                                no_link_if_err: params[:no_link_if_err]   }
              )
            else
              dl_index += 1
            end
          end
        else
          data_links << Link.new({
                                   rel: run_key_transform(params[:rel]),
                                   system: params[:system].presence || '',
                                   link_method_name: params[:link_method_name].presence || block,
                                   type: params[:type].presence || "GET",
                                   no_link_if_err: params[:no_link_if_err] }
          )
        end
      end

    end
  end
end
