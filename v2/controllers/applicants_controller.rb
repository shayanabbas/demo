module Api
  module V2
    class ApplicantsController < Api::V2::ApiController

      skip_before_action :verify_authenticity_token, :only => [:create]
      before_action :validate_api_request, :only => [:create]

      def create
        data = {}

        unless params[:applicant][:consents].blank?
          consents = params[:applicant].delete(:consents)
          consent_text_id = consents[:consent_text_id].to_i unless consents[:consent_text_id].blank?
          consent = Consent.of_organization(current_api_organization.id).for_consent_text(consent_text_id).active.first unless consent_text_id.blank?
        end

        applicant = Applicant.new(params[:applicant])
        applicant.organization_id = current_api_organization.id
        applicant.applicant_state_id = ApplicantState::IN_PROGRESS
        applicant.consent_id = consent.id if consent
        applicant.created_user_id = User::WEBSITE_ID
        applicant.updated_user_id = User::WEBSITE_ID
        applicant.save
        if not applicant.id.present? or not applicant.errors.blank?
          data = { :errors => applicant.errors.full_messages.to_sentence, :success => false }
        else
          applicant.send_application_email
          data = { :id => applicant.id.to_s, :success => true }
        end
        render json: data
      end

      def applicant_params
        params.require(:applicant).permit(:first_name, :last_name, :address, :zip, :city, :birth_year, :birthday, :email, :phone, :service_id, :consents => [:consent_text_id])
      end

    end
  end
end