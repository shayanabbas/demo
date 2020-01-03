module Api
  module V2
    class BanksController < Api::V2::ApiController

      before_filter :validate_api_request

      def index
        render json: Bank.get_banks
      end

    end
  end
end