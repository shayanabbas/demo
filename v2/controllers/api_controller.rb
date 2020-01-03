module Api
  module V2
    class ApiController < ApplicationController

      respond_to :xml, :json
      before_filter :restrict_access
      before_filter :set_access_control_headers
      skip_before_filter :restrict_access, :only => [:options]
      skip_before_filter :verify_authenticity_token, :if => :organization_api_request || :user_api_request

      def options
        render :text => '', :content_type => 'text/plain'
      end

      protected

      rescue_from ApiErrorHandling::Exceptions::BaseException, :with => :rescue_api_error
      rescue_from ActionController::ParameterMissing, :with => :rescue_api_error

      def rescue_api_error(e)
        set_access_control_headers
        logger.error "An error was encountered in the API. Exception: #{e.inspect}"
        @exception = e
        @ex_class = e.class
        @error_message = @exception.message.blank? ? @ex_class::DESCRIPTION : @exception.message
        status = 400
        status = @ex_class::STATUS if defined? @ex_class::STATUS
        render :json => {:error => @error_message, :status => status}, :status => status
      end

      def extract_from_params(nested_key = nil, *keys)
        if nested_key.blank?
          params.dup.symbolize_keys.reject{|k,v| !keys.include?(k) }
        else
          params[nested_key].dup.symbolize_keys.reject{|k,v| !keys.include?(k) }
        end
      end

      def set_access_control_headers
        headers['Access-Control-Allow-Origin'] = '*'
        headers['Access-Control-Allow-Methods'] = 'POST, PUT, DELETE, GET, OPTIONS'
        headers['Access-Control-Request-Method'] = '*'
        headers['Access-Control-Allow-Headers'] = '*, X-Requested-With, X-Prototype-Version, X-CSRF-Token, Content-Type'
        headers['Access-Control-Max-Age'] = "1728000"
      end

      def validate_api_request
        allowed = false
        remote_ip = request.remote_ip

        host = request_host
        Rails.logger.info("\nAPI request from host #{host} and ip #{remote_ip} => #{controller_name}/#{action_name}")

        return if Rails.env.test?

        # Convert remote IP to an integer.
        bremote_ip = remote_ip.split('.').map(&:to_i).pack('C*').unpack('N').first

        ApiAcl.of_organization(current_api_organization.id).each do |acl|
          ip, mask = acl.allowed_ip.split '/'

          # Convert tested IP to an integer.
          bip = ip.split('.').map(&:to_i).pack('C*').unpack('N').first

          # Convert mask to an integer, and assume /32 if not specified.
          mask = mask ? mask.to_i : 32
          bmask = ((1 << mask) - 1) << (32 - mask)
          if bip & bmask == bremote_ip & bmask
            allowed = (controller_name == acl.controller_name && (action_name == acl.action_name || acl.action_name.blank?) )
            break if allowed
          end
        end

        raise AclException, "Access not allowed from IP #{remote_ip}" unless allowed
      end

      def set_user_from_params
        begin
          @user = (current_user.present? ? current_user : User.find_by_username(params[:username]))
        rescue ActiveRecord::RecordNotFound => e
          Rails.logger.error e.to_s
          raise ResourceNotFoundException, "User not found."
        end
      end

      private

      def restrict_access
        has_access = false
        if organization_api_request
          api_key = ApiKey.find_by_access_token(params[:api_key])
          has_access = !api_key.nil?
        elsif user_api_request
          has_access = !current_user.nil?
        end
        raise AuthenticationError, "Incorrect authentication credentials." unless has_access
      end

      def current_api_organization
        if organization_api_request
          @current_api_organization ||= ApiKey.get_organization(params[:api_key])
        elsif user_api_request
          @current_api_organization ||= ApiSession.organization_by_api_key(params[:api_session_id])
        else
          @current_api_organization = nil
        end
      end
      helper_method :current_api_organization

      def current_user
        if user_api_request
          @current_user ||= ApiSession.user_by_api_key(params[:api_session_id], DeviceDetector.new(request.user_agent), params[:cs])
        else
          @current_user = nil
        end
      end
      helper_method :current_user

      def organization_api_request
        params.has_key?(:api_key)
      end

      def user_api_request
        params.has_key?(:api_session_id)
      end

    end
  end
end
