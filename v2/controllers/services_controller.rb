module Api
  module V2
    class ServicesController < Api::V2::ApiController

      before_filter :validate_api_request

      def index
        services = Service.select([:id, :name, :info]).of_organization(current_api_organization.id)

        if !params[:service_type_id].blank? && params[:service_type_id].to_i > 0
          services = services.of_service_type(params[:service_type_id].to_i)
        end

        if !params[:show_for_applicants].blank? && params[:show_for_applicants] == 'true'
          services = services.where(:show_for_applicants => true)
        end

        render :status => :ok, json: services
      end

    end
  end
end