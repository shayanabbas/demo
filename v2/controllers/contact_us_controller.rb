module Api
  module V2
    class ContactUsController < Api::V2::ApiController

      skip_before_filter :restrict_access, :only => [:create]

      def create
        status = :bad_request
        contact_us = ContactUs.init(params, current_user)
        if contact_us.valid? and contact_us.send_email(current_user)
          status = :ok
        end
        render json: { :status => status }
      end

    end
  end
end