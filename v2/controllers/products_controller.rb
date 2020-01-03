module Api
  module V2
    class ProductsController < Api::V2::ApiController

      before_filter :validate_api_request

      def index
        products = Product.of_organization(current_api_organization.id).active

        if !params[:service_type_id].blank? && params[:service_type_id].to_i > 0
          product_category_ids = Product.select(:product_category_id).of_organization(current_api_organization.id).of_service_type(params[:service_type_id].to_i).map(&:product_category_id).uniq
          products = products.where(:product_category_id => product_category_ids) unless product_category_ids.blank?
        end

        if !params[:e_commerce_product].blank? && params[:e_commerce_product].to_i == 1
          products = products.where(:e_commerce_product => 1)
        end

        I18n.with_locale(I18n.locale) do
          results = []
          products.each do |product|
            results << {
                :id => product.id,
                :name => product.name,
                :description => product.description,
                :product_code => product.product_code,
                :vat_percent => product.vat_percent,
                :price => product.price,
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