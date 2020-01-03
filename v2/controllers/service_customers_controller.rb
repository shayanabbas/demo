module Api
  module V2
    class ServiceCustomersController < Api::V2::ApiController

      before_filter :validate_api_request
      before_action :set_service_customer, :only => [:show]

      def show
        I18n.with_locale(I18n.locale) do

          results = {
              :service_customer_id => @service_customer.id,
              :customer_type_id => @service_customer.customer.customer_type_id,
              :name => @service_customer.customer.name,
              :first_name => @service_customer.customer.first_name,
              :last_name => @service_customer.customer.last_name,
              :email => @service_customer.customer.email,
              :address => @service_customer.customer.address,
              :zip => @service_customer.customer.zip,
              :city => @service_customer.customer.city,
              :amount => @service_customer.amount,
              :service_id => @service_customer.service_id,
              :service_name => @service_customer.service.name,
              :product_id => @service_customer.product_id,
              :product_name => @service_customer.product.name,
          }

          respond_to do |format|
            format.json { render :json => results }
          end
        end
      end

      private

      def set_service_customer
        @service_customer = ServiceCustomer.find_by_id(params[:id])
        raise ApiErrorHandling::Exceptions::ResourceNotFoundException, "no service customer found for id #{params[:id]}" unless @service_customer
        if params[:access_token].blank?
          raise ApiErrorHandling::Exceptions::ResourceNotFoundException, "access token missing"
        else
          unless @service_customer.customer.person.valid_token?(params[:access_token])
            raise ApiErrorHandling::Exceptions::InvalidParametersError, "incorrect access token"
          end
        end
      end

    end
  end
end