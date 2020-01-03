module Api
  module V2
    class FundraisingsController < Api::V2::ApiController

      before_filter :validate_api_request

      def index
        fundraisings = ::Fundraising.select([:id, :title, :info]).of_organization(current_api_organization.id).active.order(:title)

        if !params[:fundraising_type_id].blank? && params[:fundraising_type_id].to_i > 0
          fundraisings = fundraisings.of_fundraising_type(params[:fundraising_type_id].to_i)
        end

        render :status => :ok, json: fundraisings
      end

      def create
        fundraising = Api::Fundraising.init(params[:fundraising], current_api_organization, params[:locale])
        if fundraising.valid?
          person, fundraising_customer, success, exception = fundraising.create_person_and_fundraising
          if success
            unless fundraising_customer.nil?
              fundraising_customer_id = fundraising_customer.id
              checksum = fundraising_customer.api_checksum
            end
            render json: { :status => :ok, :customer_id => person.customer_id, :fundraising_customer_id => fundraising_customer_id, :fundraising_customer_checksum => checksum }
          else
            log_error(exception.to_s)
            message = t('api.fundraising.create.error')
            if exception.class == ApiErrorHandling::Exceptions::ResourceNotFoundException
              raise ResourceNotFoundException, exception.to_s
            else
              raise ApplicationError, message
            end
          end
        else
          raise MissingParametersError, fundraising.errors.full_messages
        end
      end

      def fundraising_params
        params.permit(:api_key, :locale, :first_name, :last_name, :address, :zip, :city, :email, :phone, :fundraising_id, :fundraising_type_id, :fundraising_customer_state_id, :amount, :event_date, :payment_message, :message, :customer_reference, :contact_method_id, :results_info_contact_method_id, :external_link_url, :service_id, :company_name, :company_extension, :vat_number, :intermediator_id, :einvoicing_address, :anonymous, :only_service, :client_ip_address, :group_ids => [:group_id], :consents => [:consent_text_id],
                      :fundraising => [:first_name, :last_name, :address, :zip, :city, :email, :phone, :fundraising_id, :fundraising_type_id, :fundraising_customer_state_id, :amount, :event_date, :payment_message, :message, :customer_reference, :contact_method_id, :results_info_contact_method_id, :external_link_url, :service_id, :company_name, :company_extension, :vat_number, :intermediator_id, :einvoicing_address, :anonymous, :only_service, :client_ip_address, :group_ids => [:group_id], :consents => [:consent_text_id]]
        )
      end

    end
  end
end