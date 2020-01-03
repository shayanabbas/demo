module Api
  module V2
    class ConsentTextsController < Api::V2::ApiController

      respond_to :xml, :json
      before_filter :validate_api_request

      def index
        begin
          consents = Consent.of_organization(current_api_organization.id).active
          consents = consents.for_services([params[:service_id].to_i]) if !params[:service_id].blank? && params[:service_id].to_i > 0

          I18n.with_locale(I18n.locale) do
            results = []
            consents.each do |consent|
              results << {
                  :id => consent.consent_text.id,
                  :version_number => consent.version_number,
                  :title => consent.title,
                  :foreword => consent.foreword,
                  :consent => consent.consent,
              }
            end

            respond_to do |format|
              format.xml  { render :xml => results.to_xml(:root => 'concents') }
              format.json { render :json => results }
            end

          end
        rescue => e
          Rails.logger.error e.to_s
        end
      end

    end
  end
end