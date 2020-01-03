module Api
  module V2
    class CountriesController < Api::V2::ApiController

      before_filter :validate_api_request

      def index
        I18n.with_locale(I18n.locale) do
          results = []

          countries = Country.where(:code_2 => ExternalApp::STRIPE_COUNTRIES).order("#{I18nHelper.i18n_name_field_name}")
          countries.each do |country|
            results << {
                :id => country.id,
                :name => country.name,
                :code_2 => country.code_2,
                :code_3 => country.code_3,
                :default => country.code_2 == IbanHelper::DEFAULT_COUNTRY_CODE
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