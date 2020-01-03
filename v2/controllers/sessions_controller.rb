module Api
  module V2
    class SessionsController < Api::V2::ApiController

      skip_before_filter :verify_authenticity_token
      skip_before_filter :restrict_access, :only => [:create]

      def create
        client = DeviceDetector.new(request.user_agent)
        auth_status, organizations, api_session = ApiSession.create_session_or_authenticate(params, client)
        render json: { :auth_status => auth_status, :organizations => organizations, :api_session => api_session }
      end
    end
  end
end