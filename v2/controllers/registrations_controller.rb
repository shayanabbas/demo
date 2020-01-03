module Api
  module V2
    class RegistrationsController < Api::V2::ApiController

      before_filter :validate_api_request

      def create
        registration = Api::Registration.init(params[:registration], current_api_organization, params[:locale])
        if registration.valid?
          person, success, exception = registration.create_person
          if success
            render json: { :status => :ok, :customer_id => person.customer_id }
          else
            log_error(exception.to_s)
            message = t('api.registration.create.error')
            if exception.class == ApiErrorHandling::Exceptions::ResourceNotFoundException
              raise ResourceNotFoundException, exception.to_s
            else
              raise ApplicationError, message
            end
          end
        else
          raise MissingParametersError, registration.errors.full_messages
        end
      end

      def registration_params
        params.require(:registration).permit(:first_name, :last_name, :address, :zip, :city, :email, :phone, :title, :info, :customer_reference, :company_name, :company_extension, :vat_number, :intermediator_id, :einvoicing_address, :invoicing_address, :invoicing_address2, :invoicing_zip, :invoicing_city, :client_ip_address, :group_ids => [:group_id], :consents => [:consent_text_id])
      end

    end
  end
end