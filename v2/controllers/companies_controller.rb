module Api
  module V2
    class CompaniesController < Api::V2::ApiController

      before_filter :get_company, :only => :employees

      def employees
        raise ApiErrorHandling::Exceptions::ResourceNotFoundException, "no company found for id #{params[:id]}" unless @company

        @employees = @company.employees.where(:organization_id => current_api_organization.id, :person_state_id => PersonState::ACTIVE)

        fields = [:id, :first_name, :last_name, :title, :email, :phone_work, :phone_mobile, :zip, :city]

        respond_to do |format|
          format.xml  { render :xml => @employees.to_xml( :only => fields ) }
          format.json { render :json => @employees.to_json( :only => fields ) }
        end
      end

      def get_company
        @company = Company.of_organization(current_api_organization.id).find(params[:company_id])
      end

    end
  end
end