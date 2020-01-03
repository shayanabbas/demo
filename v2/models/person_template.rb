class Api::PersonTemplate
  include ActiveModel::Validations
  include ActiveModel::Conversion
  extend ActiveModel::Naming

  attr_accessor :first_name, :last_name, :address, :zip, :city, :country_id, :email, :phone, :company, :birthday, :birth_year, :contact_method_id, :group_membership_state_id, :service_id, :product_id, :group_ids, :locale, :external_id, :user_id, :organization_id, :consents, :client_ip_address

  validates_presence_of :first_name, :last_name, :organization_id
  validates_presence_of :contact_method_id, :unless => Proc.new { |model| model.class.name == "Api::Feedback" }
  validates :email, :email => true, :if => :contact_method_email?
  validates_presence_of :address, :zip, :city, :if => :contact_method_post?

  def self.init(params, organization, data = nil)
    data = self.new if data.nil?
    data.organization_id = organization.id

    data.first_name = params[:first_name].strip.capitalize unless params[:first_name].blank?
    data.last_name = params[:last_name].strip.capitalize unless params[:last_name].blank?

    unless params[:address].blank?
      address = params[:address].strip
      if address.index(' ')
        street_address = address.split(' ').first
        street_number = address.split(' ',2).last
        address = "#{street_address.capitalize} #{street_number}"
      end
      data.address = address
    end
    data.zip = params[:zip].strip unless params[:zip].blank?
    data.city = params[:city].strip.capitalize unless params[:city].blank?
    data.country_id = params[:country_id].to_i unless params[:country_id].blank?
    data.email = params[:email].strip unless params[:email].blank?
    data.phone = params[:phone].strip unless params[:phone].blank?
    data.company = params[:company].strip.capitalize unless params[:company].blank?

    data.birth_year = params[:birth_year].to_i unless params[:birth_year].blank?
    data.birthday = params[:birthday] unless params[:birthday].blank?

    data.group_ids = []
    unless params[:group_ids].blank?
      params[:group_ids].each do |group|
        data.group_ids << group['group_id'].to_i unless group['group_id'].blank?
      end
    end

    data.contact_method_id = params[:contact_method_id].to_i unless params[:contact_method_id].blank?
    data.group_membership_state_id = params[:group_membership_state_id].to_i unless params[:group_membership_state_id].blank?
    data.service_id = params[:service_id].to_i unless params[:service_id].blank?
    data.product_id = params[:product_id].to_i unless params[:product_id].blank?
    data.locale = params[:locale].to_sym unless params[:locale].blank?

    data.client_ip_address = params[:client_ip_address].strip unless params[:client_ip_address].blank?
    data.consents = []
    unless params['consents'].blank?
      params['consents'].each do |consent|
        data.consents << (consent.instance_of?(Fixnum) ? consent : consent['consent_text_id'].to_i)
      end
    end

    data.external_id = params[:external_id].strip unless params[:external_id].blank?
    data.user_id = params[:user_id] unless params[:user_id].blank?
    data
  end

  def name
    "#{first_name} #{last_name}"
  end

  private

  def contact_method_email?
    contact_method_id == ContactMethod::EMAIL
  end

  def contact_method_post?
    contact_method_id == ContactMethod::POST
  end

end