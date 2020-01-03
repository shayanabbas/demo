module Api
  module V2
    class NewsletterOrdersController < Api::V2::ApiController
      
      before_filter :validate_api_request

      def create
        order = Api::NewsletterOrder.init(params[:newsletter_order], current_api_organization)
        if order.valid?
          person, success, exception = order.create_person_and_memberships
          if success
            render json: { :status => :ok, :customer_id => person.customer_id }
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

      def newsletter_order_params
        params.require(:newsletter_order).permit(:first_name, :last_name, :contact_method_id, :email, :address, :zip, :city, :phone, :client_ip_address, :external_id, :group_ids => [:group_id], :consents => [:consent_text_id])
      end

    end
  end
end