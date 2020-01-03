module Api
  module V2
    class InvoicesController < Api::V2::ApiController

      protect_from_forgery :except => [:create_from_commerce_order]
      respond_to :json

      def create_commerce_donation
        order_params    = params[:order]
        customer_params = params[:customer]
        person = nil

        if params.has_key?(:customer) 
          if customer_params[:is_customer] == 'true'
            customer = Api::ExternalCustomer.init(customer_params, current_api_organization)
            person, success, exception = customer.create_person
            if !success
              person = nil
            end
          else
            order_params[:customer] = customer_params
          end
        end
        
        errors = Invoice.create_from_commerce_donation(order_params, current_api_organization, person)
        if errors.blank?
          render json: { :status => :ok }
        else
          render json: { :errors => errors }
        end
      end

    end
  end
end