module Api
  module V2
    class GroupsController < Api::V2::ApiController

      before_filter :validate_api_request

      def index
        groups = Group.select([:id, :name, :info]).of_organization(current_api_organization.id).active

        if !params[:group_type_id].blank? && params[:group_type_id].to_i > 0
          groups = groups.of_group_type(params[:group_type_id].to_i)
        end

        render json: groups
      end

    end
  end
end