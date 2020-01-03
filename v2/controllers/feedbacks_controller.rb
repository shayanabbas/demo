module Api
  module V2
    class FeedbacksController < Api::V2::ApiController

      before_filter :validate_api_request

      def create
        feedback = Api::Feedback.init(params[:feedback], current_api_organization)
        if feedback.valid?
          person, success, exception = feedback.create_person_and_memberships
          if person.valid?
            if success
              render json: { :status => :ok, :customer_id => person.customer_id }
            else
              log_error(exception.to_s)
              message = t('api.feedback.create.error')
              if exception.class == ApiErrorHandling::Exceptions::ResourceNotFoundException
                raise ResourceNotFoundException, exception.to_s
              else
                raise ApplicationError, message
              end
            end
          else
            raise MissingParametersError, person.errors.full_messages
          end
        else
          raise MissingParametersError, feedback.errors.full_messages
        end
      end

      def feedback_params
        params.require(:feedback).permit(:first_name, :last_name, :email, :phone, :title, :feedback_text, :client_ip_address, :group_ids => [:group_id], :consents => [:consent_text_id])
      end

    end
  end
end