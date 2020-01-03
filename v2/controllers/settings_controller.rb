module Api
  module V2
    class SettingsController < Api::V2::ApiController

      before_filter :validate_api_request

      def index
        results = {}
        organization = current_api_organization

        results = {
            :name => organization.name,
            :address => organization.address,
            :website => organization.website,
            :contact_email => organization.contact_email,
            :vat_number => organization.vat_number,
            :logo_url => organization.main_logo,
            :background_color => organization.background_color,
        } if organization

        respond_to do |format|
          format.json { render :json => results }
        end
      end

    end
  end
end
