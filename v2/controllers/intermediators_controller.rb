module Api
  module V2
    class IntermediatorsController < Api::V2::ApiController

      before_filter :validate_api_request

      def index
        intermediators = Intermediator.select([:id, :name, :intermediator_code]).order(:name)
        render json: intermediators
      end

    end
  end
end