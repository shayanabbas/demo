module Api
  module V2
    class MagazineOrdersController < Api::V2::ApiController

      skip_before_filter  :verify_authenticity_token

      def create
        order = Api::MagazineOrder.init(params, current_api_organization)
        if order.valid?
          channel_id = (request.host.include?('facebook') ? ContactMethod::FACEBOOK : ContactMethod::WEBSITE)
          person, success, exception = order.create_person_and_service_customer(channel_id)
          if success
            render json: { :status => :ok }
          else
            log_error(exception.to_s)
            message = t('api.newsletter_order.create.error')
            if exception.class == ApiErrorHandling::Exceptions::ResourceNotFoundException
              raise ResourceNotFoundException, exception.to_s
            else
              raise ApplicationError, message
            end
          end
        else
          raise MissingParametersError, order.errors.full_messages
        end
      end

      def magazine_order_params
        params.permit(:first_name, :last_name, :address, :zip, :city, :email, :phone, :company, :contact_method_id, :service_id, :locale, :client_ip_address, :consents => [:consent_text_id])
      end

    end
  end
end