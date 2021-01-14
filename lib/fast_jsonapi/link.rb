require 'fast_jsonapi/scalar'

module FastJsonapi
  class Link < Scalar
    attr_reader :rel, :system, :type, :link_method_name
    def initialize(params, options: {})
      @rel = params[:rel]
      @system = params[:system]
      @type = params[:type]

      super(key: :_link, method: params[:link_method_name], options: options)
    end

    def serialize(record, serialization_params, output_array)
      if conditionally_allowed?(record, serialization_params)
        if method.is_a?(Proc)
          output_array << {
            rel: @rel,
            system: @system.presence || serialization_params[:system_type] || '',
            type: @type,
            href: FastJsonapi.call_proc(method, record, serialization_params)
          }
        else
          output_array << {
            rel: @rel,
            system: @system.presence || serialization_params[:system_type] || '',
            type: @type,
            href: "#{record.public_send(method)}"
          }
        end
      end
    end

    def self.serialize_rails_simple_self(id, record_type, serialization_params)
      return [{
        rel: :self,
        system: serialization_params[:system_type] || '',
        type: "GET",
        href: "/#{record_type.to_s.pluralize}/#{id}"
      }]
    end
  end
end
