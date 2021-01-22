require 'fast_jsonapi/constants'
module FastJsonapi
  class Relationship
    include Constants
    attr_reader :owner, :key, :name, :id_method_name, :record_type, :object_method_name, :object_block, :serializer, :relationship_type, :polymorphic, :conditional_proc, :transform_method, :lazy_load_data

    def initialize(
      owner:,
      key:,
      name:,
      id_method_name:,
      record_type:,
      object_method_name:,
      object_block:,
      serializer:,
      relationship_type:,
      polymorphic:,
      conditional_proc:,
      transform_method:,
      lazy_load_data: false
    )
      @owner = owner
      @key = key
      @name = name
      @id_method_name = id_method_name
      @record_type = record_type
      @object_method_name = object_method_name
      @object_block = object_block
      @serializer = serializer
      @relationship_type = relationship_type
      @polymorphic = polymorphic
      @conditional_proc = conditional_proc
      @transform_method = transform_method
      @lazy_load_data = lazy_load_data
      @record_types_for = {}
      @serializers_for_name = {}
    end

    def serialize(record, original_options, serialization_params, output_hash, fieldset_current_level)
      if include_relationship?(record, serialization_params)

        data = relationship_type == :has_many ? [] : nil
        relevant_objs = fetch_associated_object(record, serialization_params)

        if relevant_objs.present?
          initialize_static_serializer unless @initialized_static_serializer

          if relationship_type == :has_many
            if @static_serializer && ((original_options&.dig(:nest_level) || 0) <= NEST_MAX_LEVEL)
              data = relevant_objs.each_with_object([]) do |sub_obj, array|
                array << serialize_deep(sub_obj, original_options, fieldset_current_level)
              end
            else
              data = ids_hash_from_record_and_relationship(record, serialization_params) || empty_case unless lazy_load_data && ((original_options&.dig(:nest_level) || 0) <= (NEST_MAX_LEVEL + 1))
            end
          else
            if @static_serializer && ((original_options&.dig(:nest_level) || 0) <= NEST_MAX_LEVEL)
              data = serialize_deep(relevant_objs, original_options, fieldset_current_level)
            else
              data = ids_hash_from_record_and_relationship(relevant_objs, serialization_params) || empty_case unless lazy_load_data && ((original_options&.dig(:nest_level) || 0) <= (NEST_MAX_LEVEL + 1))
            end
          end
        end
        output_hash[@key] = data

      end
    end

    def serialize_deep(relevant_obj, original_options, fieldset_current_level)
      appropriate_field = fieldset_current_level.detect { |f| (f.is_a?(Hash) && f.keys.first == @key) || f==@key } if fieldset_current_level
      new_original_options = original_options.dup
      if fieldset_current_level
        if appropriate_field.nil?
          new_original_options[:fields] = [] # meaning, we provided a fieldset into the serialization world, but not this relationship
        elsif appropriate_field.is_a?(Hash) # subfields specified for this key
          new_original_options[:fields] = appropriate_field[@key] # jump one step down
        elsif appropriate_field.is_a?(Symbol) # this relationships key is in the fieldset
          new_original_options.except!(:fields) # removing.. meaning all fields (and sub relationships)
        else
          new_original_options[:fields] = [] # emit nothing for the relationship
        end
      else
        new_original_options.except!(:fields) # remove meaning all fields
      end

      @static_serializer.new(relevant_obj, new_original_options).serializable_hash
    end

    def fetch_associated_object(record, params)
      return FastJsonapi.call_proc(object_block, record, params) unless object_block.nil?

      record.send(object_method_name)
    # rescue StandardError
    #   return nil  # tollerate mistakes by not outputting
    end

    def include_relationship?(record, serialization_params)
      if conditional_proc.present?
        FastJsonapi.call_proc(conditional_proc, record, serialization_params)
      else
        true
      end
    end

    def static_serializer
      initialize_static_serializer unless @initialized_static_serializer
      @static_serializer
    end

    def static_record_type
      initialize_static_serializer unless @initialized_static_serializer
      @static_record_type
    end

    def get_json_field_name
      @key
    end

    def get_name
      @name
    end

    private

    def ids_hash_from_record_and_relationship(record, params = {})
      initialize_static_serializer unless @initialized_static_serializer

      return ids_hash(fetch_id(record, params), @static_record_type, params) # if @static_record_type

    end


    def ids_hash(ids, record_type, params)
      return ids.map { |id| id_hash(id, record_type, params) } if ids.respond_to? :map

      id_hash(ids, record_type, params) # ids variable is just a single id here
    end

    def id_hash(id, record_type, params, default_return = false)
      if id.present?
        { id: id.to_s, _links: trivial_link_hash(id, record_type, params) } # optimized for large data sets
      else
        default_return ? { id: nil } : nil
      end
    end

    def trivial_link_hash(id, record_type, params = {})
      Link.serialize_rails_simple_self(id, record_type, params)
    end

    def fetch_id(record, params)
      if object_block.present?
        object = FastJsonapi.call_proc(object_block, record, params)
        return object.map { |item| item.public_send(id_method_name) } if object.respond_to? :map

        return object.try(id_method_name)
      end
      record.public_send(id_method_name)
    # rescue StandardError
    #   nil # tollerate mistakes and output nothing
    end

    def run_key_transform(input)
      if transform_method.present?
        input.to_s.send(*transform_method).to_sym
      else
        input.to_sym
      end
    end

    def initialize_static_serializer
      return if @initialized_static_serializer

      @static_serializer = compute_static_serializer
      @static_record_type = compute_static_record_type
      @initialized_static_serializer = true
    end

    def compute_static_serializer
      if polymorphic
        # polymorphic without a specific serializer --
        # the serializer is determined on a record-by-record basis
        nil

      elsif serializer.is_a?(Symbol) || serializer.is_a?(String)
        # a serializer was explicitly specified by name -- determine the serializer class
        serializer_for_name(serializer)

      elsif serializer.is_a?(Proc)
        # the serializer is a Proc to be executed per object -- not static
        nil

      elsif serializer
        # something else was specified, e.g. a specific serializer class -- return it
        serializer

      elsif object_block
        # an object block is specified without a specific serializer --
        # assume the objects might be different and infer the serializer by their class
        nil

      else
        # no serializer information was provided -- infer it from the relationship name
        serializer_name = name.to_s
        serializer_name = serializer_name.singularize if relationship_type.to_sym == :has_many
        serializer_for_name(serializer_name)
      end
    end

    def serializer_for_name(name)
      @serializers_for_name[name] ||= owner.serializer_for(name)
    rescue NameError
      @serializers_for_name[name] ||= nil
    end


    def compute_static_record_type
      if polymorphic
        nil
      elsif record_type
        run_key_transform(record_type)
      elsif @static_serializer
        run_key_transform(@static_serializer.record_type)
      end
    end
  end
end
