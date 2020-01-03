module Api
  module V2
    class ChargesController < Api::V2::ApiController

      before_filter :validate_api_request

      def create
        success = false

        begin
          external_app = current_api_organization.get_external_app(ExternalApp::STRIPE)
          unless external_app
            errors = "Organization does not have active #{ExternalApp.find(ExternalApp::STRIPE).name} external app."
            raise ApiErrorHandling::Exceptions::InvalidParametersError
          else
            Stripe.api_key = external_app.secret_key

            external_customer = Api::ExternalCustomer.init(params[:charge], current_api_organization)
            unless external_customer.valid?
              errors = external_customer.errors.full_messages
              raise ApiErrorHandling::Exceptions::InvalidParametersError
            else
              service = nil
              person = nil
              stripe_customer_id = nil
              stripe_customer = nil
              user_id = User::STRIPE_ID
              amount = params[:amount].to_i

              if amount < current_api_organization.minimum_recurring_amount
                errors = "Amount #{amount} is less than minimum amount #{current_api_organization.minimum_recurring_amount}."
                raise ApiErrorHandling::Exceptions::InvalidParametersError
              else

              service = Service.of_organization(current_api_organization.id).find_by_id(external_customer.service_id) unless external_customer.service_id.blank?
              unless service
                errors = "Service ID #{external_customer.service_id} not found."
                raise ApiErrorHandling::Exceptions::InvalidParametersError
              else
                product = Product.of_organization(current_api_organization.id).find_by_id(external_customer.product_id) unless external_customer.product_id.blank?
                product_id = product.nil? ? service.product_id : product.id

                person = Person.duplicates(current_api_organization.id, external_customer.first_name, external_customer.last_name, external_customer.address, external_customer.zip, external_customer.email).first
                if person
                  if person.active? || person.passivated?
                    external_app_customer = person.external_customer_for_app(ExternalApp::STRIPE)
                    if external_app_customer
                      stripe_customer_id = external_app_customer.external_id
                    end
                  end
                end

                unless stripe_customer_id
                  # if Stripe customer was not already found
                  # https://stripe.com/docs/api/customers/create
                  stripe_customer = Stripe::Customer.create(
                      :email => external_customer.email,
                      :source  => params[:stripeToken],
                      :shipping => { :name => external_customer.name, :address => {:line1 => external_customer.address, :city => external_customer.city, :postal_code => external_customer.zip, :country => params[:country]} }
                  )
                  stripe_customer_id = stripe_customer.id
                end

                for_year = Date.today.year
                for_month = Date.today.month

                if stripe_customer_id
                  charge = Stripe::Charge.create(
                      :customer    => stripe_customer_id,
                      :amount      => (100 * amount).to_i, # the amount is defined in cents
                      :description => "#{service.name} #{for_year}/#{for_month}",
                      :currency    => DEFAULT_CURRENCY
                  )
                  if charge
                    unless person
                      person, success, exception = external_customer.create_person
                    end

                    unless external_app_customer
                      external_app_customer = person.create_external_customer_for_app(ExternalApp::STRIPE, stripe_customer_id)
                    end

                    if person and external_app_customer
                      today_of_month = Date.today.day
                      due_day_of_month = (today_of_month > 28 ? 28 : today_of_month) # billing day for card payments can be max. 28th day of month, so that billing is possible also in February
                      service_customer = ServiceCustomer.create!(:customer_id => person.customer_id, :amount => amount, :service_id => service.id, :product_id => product_id, :invoice_type_id => InvoiceType::CREDIT_CARD_ID, :service_state_id => ServiceState::ACTIVE, :due_day_of_month => due_day_of_month, :started_at => Time.now, :channel_contact_method_id => ContactMethod::WEBSITE, :contact_method_id => ContactMethod::EMAIL, :created_user_id => user_id, :updated_user_id => user_id)
                      if service_customer
                        result, errors, invoice = Invoice.create_service_invoice_for_month(service, service_customer, service.organization, for_month, for_year, nil, charge.id, today_of_month)
                        if invoice
                          invoice.create_payment_and_mark_paid(Date.today, amount, person.name, charge.id, user_id)

                          # let's create access_token for person, so that e.g. expiring credit card can be later updated
                          access_token = person.generate_token!

                          UserMailer.donation_thank_you_email(service_customer).deliver_later(wait: 1.minute)
                          success = true
                        end
                      end
                    end
                  end
                end
              end

              end
            end
          end
        rescue Stripe::CardError => e
          Rails.logger.error "Stripe::CardError: #{e.inspect}"
          body = e.json_body
          err  = body[:error]
          Rails.logger.error "Status: #{e.http_status}"
          Rails.logger.error "Type: #{err[:type]}"
          Rails.logger.error "Charge ID: #{err[:charge]}"
          Rails.logger.error "Code: #{err[:code]}"
          Rails.logger.error "Decline code: #{err[:decline_code]}"
          Rails.logger.error "Message: #{err[:message]}"
          Rails.logger.error "Doc URL: #{err[:doc_url]}"
          @error_message = I18n.t("payment_gateways.stripe.error_codes.#{err[:code]}")
          @error_message = err[:message] if @error_message.include?('missing')
          render :error
        rescue Stripe::RateLimitError => e
          # Too many requests made to the API too quickly
        rescue Stripe::InvalidRequestError => e
          # Invalid parameters were supplied to Stripe's API
        rescue Stripe::AuthenticationError => e
          # Authentication with Stripe's API failed (maybe you changed API keys recently)
        rescue Stripe::APIConnectionError => e
          # Network communication with Stripe failed
        rescue Stripe::StripeError => e
          # Display a very generic error to the user, and maybe send yourself an email
        rescue => ex
          # Something else happened, completely unrelated to Stripe
        ensure
          if success
            render json: { :name => person.name, :email => person.email, :customer_number => person.customer_number, :service_name => service.name, :amount => service_customer.amount }
          else
            Rails.logger.error e.to_s
            unless e.blank?
              errors = e.json_body[:error][:message]
            end
            raise ApiErrorHandling::Exceptions::InvalidParametersError, errors
          end
        end
      end

      def charge_params
        params.require(:charge).permit(:first_name, :last_name, :email, :address, :zip, :city, :phone, :country_id, :service_id, :product_id, :amount, :birth_year, :contact_method_id, :stripeToken, :group_ids => [:group_id], :consents => [:consent_text_id])
      end

    end
  end
end