module Api
  module V2
    class FundraisingCustomersController < Api::V2::ApiController

      before_filter :validate_api_request
      before_action :set_fundraising_customer

      def update
        customer = Api::Customer.init(params[:fundraising_customer], current_api_organization)
        if customer.valid?
          person, success, exception = customer.find_or_create_person(@fundraising_customer)
          if success
            render json: { :status => :ok, :customer_id => person.customer_id }
          else
            log_error(exception.to_s)
            if exception.class == ApiErrorHandling::Exceptions::ResourceNotFoundException
              raise ResourceNotFoundException, exception.to_s
            else
              raise ApplicationError, t('api.fundraising_customer.update.error')
            end
          end
        else
          raise MissingParametersError, customer.errors.full_messages
        end
        
      end

      private

      def fundraising_customer_params
        params.require(:fundraising_customer).permit(:first_name, :last_name, :contact_method_id, :email, :address, :zip, :city, :phone, :checksum, :client_ip_address, :group_ids => [:group_id])
      end

      def set_fundraising_customer
        @fundraising_customer = FundraisingCustomer.find_by_id(params[:id])
        raise ApiErrorHandling::Exceptions::ResourceNotFoundException, "No fundraising customer found with id #{params[:id]}" unless @fundraising_customer
        raise ApiErrorHandling::Exceptions::AclException, "Incorrect organization" unless @fundraising_customer.customer.organization_id == current_api_organization.id
        raise ApiErrorHandling::Exceptions::AclException, "Fundraising customer update not allowed" unless @fundraising_customer.api_can_update?(params[:fundraising_customer][:checksum])
      end

    end
  end
end