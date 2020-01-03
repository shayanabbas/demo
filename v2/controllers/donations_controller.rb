module Api
  module V2
    class DonationsController < Api::V2::ApiController

      before_filter :validate_api_request

      def create
        data = {}
        data[:instructions] = nil
        data[:customer_number] = nil
        status = :bad_request
        donation = Api::Donation.init(params[:donation], current_api_organization, params[:locale])
        if donation.valid?
          channel_id = (request.host.include?('facebook') ? ContactMethod::FACEBOOK : ContactMethod::DONATION)
          person, success, exception = donation.create_person_and_service_customer(channel_id, User::WEBSITE_ID)
          if success
            donation.send_instructions(person.customer_number, person.customer_reference_number) unless donation.email.blank?
            data[:instructions] = donation.instructions
            data[:customer_number] = person.customer_number
            data[:reference_number] = person.customer_reference_number
            status = :ok
            render json: { :status => status, :customer_id => person.customer_id, :instructions => data[:instructions], :customer_number => data[:customer_number], :reference_number => data[:reference_number] }
          else
            log_error(exception.to_s)
            message = t('api.donation.create.error')
            if exception.class == ApiErrorHandling::Exceptions::ResourceNotFoundException
              raise ResourceNotFoundException, exception.to_s
            else
              raise ApplicationError, message
            end
          end
        else
          raise MissingParametersError, donation.errors.full_messages
        end
      end

      def create_person_and_link_to_order
        status = :bad_request
        person = Person.create_and_link_to_order(params, current_api_organization, ContactMethod::DONATION)
        unless person.nil?
          status = :ok
        end
        render json: { :status => status }
      end

      def donation_params
        params.permit(:api_key, :locale, :first_name, :last_name, :address, :zip, :city, :phone, :birth_year, :email, :contact_method_id, :amount, :bank, :due_date, :no_marketing, :service_id, :product_id, :invoice_type_id, :client_ip_address, :group_ids => [:group_id], :consents => [:consent_text_id],
                      :donation => [:first_name, :last_name, :address, :zip, :city, :phone, :birth_year, :email, :contact_method_id, :amount, :bank, :due_date, :no_marketing, :service_id, :product_id, :invoice_type_id, :client_ip_address, :group_ids => [:group_id], :consents => [:consent_text_id]]
        )
      end

    end
  end
end