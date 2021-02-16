require 'fast_jsonapi/scalar'

module FastJsonapi
  class Link < Scalar
    attr_reader :rel, :system, :type, :link_method_name, :no_link_if_err
    def initialize(params, options: {})
      @rel = params[:rel]
      @system = params[:system]
      @type = params[:type]
      @no_link_if_err = (params[:rel] == :self && params[:no_link_if_err].present?)

      super(key: :_link, method: params[:link_method_name], options: options)
    end

    def serialize(record, serialization_params, output_array)
      if conditionally_allowed?(record, serialization_params)
        add_link = true
        begin
          if method.is_a?(Proc)
            href_to_use = FastJsonapi.call_proc(method, record, serialization_params)
          else
            href_to_use = "#{record.public_send(method)}"
          end
        rescue NoMethodError
          if @no_link_if_err
            add_link = false # most likely: we auto added self link, Rails is available, and there is no rails controller to get obj
          else
            raise # serializer coding error
          end
        rescue NameError
          if @no_link_if_err
            href_to_use = "unresolvable" # almost 100% due to Rails not being available for self url_for
          else
            raise # serializer coding error
          end
        end
        output_array << {
          rel: @rel,
          system: @system.presence || serialization_params[:system_type] || '',
          type: @type,
          href: href_to_use
        } if add_link
      end
    end

    def self.serialize_rails_simple_self(id, record_type, api_namespaces, serialization_params)
      if api_namespaces.is_a?(Array)
        context_namespace = api_namespaces.reduce(""){|ctx, namespace| "#{ctx}/#{namespace}" }
      else
        context_namespace = "/#{api_namespaces}"
      end
      return [{
        rel: :self,
        system: serialization_params[:system_type] || '',
        type: "GET",
        href: "#{context_namespace}/#{record_type.to_s.pluralize}/#{id}"
      }]
    end

    def self.serialize_rails_route_self(record, record_type, api_namespaces, serialization_params)
      return [{
                rel: :self,
                system: record_type,
                type: "GET",
                href: begin "#{Rails.application.routes.url_helpers.url_for([*api_namespaces, record, only_path: true])}" rescue "unresolvable" end
              }]
    end
  end
end
