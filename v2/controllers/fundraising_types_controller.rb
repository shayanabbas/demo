module Api
  module V2
    class FundraisingTypesController < Api::V2::ApiController

      before_filter :validate_api_request

      def index
        fundraising_types = FundraisingType.all_of_organization(current_api_organization.id)

        I18n.with_locale(I18n.locale) do
          results = []
          fundraising_types.each do |fundraising_type|
            results << {
                :id => fundraising_type.id,
                :name => fundraising_type.name,
            }
          end

          respond_to do |format|
            format.json { render :json => results }
          end
        end
      end

    end
  end
end