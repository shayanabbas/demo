class Api::Registration
  include ActiveModel::Validations
  include ActiveModel::Conversion
  extend ActiveModel::Naming

  attr_accessor :organization_id, :first_name, :last_name, :address, :zip, :city, :email, :phone, :title, :language_id, :info, :customer_reference, :company_name, :company_extension, :vat_number, :intermediator_id, :einvoicing_address, :invoicing_address, :invoicing_address2, :invoicing_zip, :invoicing_city, :group_ids, :consents, :client_ip_address

  validates_presence_of :organization_id
  validates_presence_of :first_name, :last_name
  validates :email, :email => true
  validates_presence_of :address, :zip, :city

  validates_inclusion_of :intermediator_id, :in => Intermediator.select(:id).map(&:id), :allow_blank => true

  validate :vat_number_if_present

  def self.init(params, organization, locale = nil)
    data = self.new
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
    data.email = params[:email].strip unless params[:email].blank?
    data.phone = params[:phone].strip unless params[:phone].blank?
    data.title = params[:title].strip unless params[:title].blank?

    unless locale.blank?
      lang = Language.find_with_locale(locale)
      data.language_id = lang.id if lang
    end

    data.intermediator_id = params[:intermediator_id].to_i unless params[:intermediator_id].blank?
    data.einvoicing_address = params[:einvoicing_address] unless params[:einvoicing_address].blank?

    data.invoicing_address = params[:invoicing_address] unless params[:invoicing_address].blank?
    data.invoicing_address2 = params[:invoicing_address2] unless params[:invoicing_address2].blank?
    data.invoicing_zip = params[:invoicing_zip] unless params[:invoicing_zip].blank?
    data.invoicing_city = params[:invoicing_city] unless params[:invoicing_city].blank?

    data.info = params[:info].strip unless params[:info].blank?
    data.customer_reference = params[:customer_reference].strip unless params[:customer_reference].blank?

    data.company_name = params[:company_name].strip unless params[:company_name].blank?
    data.company_extension = params[:company_extension].strip unless params[:company_extension].blank?
    data.vat_number = params[:vat_number].strip unless params[:vat_number].blank?

    data.client_ip_address = params[:client_ip_address].strip unless params[:client_ip_address].blank?
    data.consents = []
    unless params['consents'].blank?
      params['consents'].each do |consent|
        data.consents << (consent.instance_of?(Fixnum) ? consent : consent['consent_text_id'].to_i)
      end
    end

    data.group_ids = []
    unless params[:group_ids].blank?
      params[:group_ids].each do |group|
        data.group_ids << group['group_id'].to_i unless group['group_id'].blank?
      end
    end

    data
  end

  def create_person
    success = true
    exception = nil
    person = nil
    company = nil
    group_membership = nil
    Person.transaction do

      person = Person.create_from_data(self, User::WEBSITE_ID)
      if person
        begin
          if !company_name.blank?
            if company = Company.create_from_data(self, User::WEBSITE_ID)
              person.employer_company_id = company.id
              person.save
            end
          end

          unless group_ids.blank?
            group_ids.each do |group_id|
              group = Group.of_organization(organization_id).find_by_id(group_id)
              if group
                existing_membership = GroupMembership.where(:group_id => group_id, :customer_id => person.customer_id).first
                unless existing_membership
                  unless self.info.blank?
                    self.info = self.info[0..199]  # group_memberships.info max length is 200
                  end
                  group_membership = person.customer.group_memberships.create!(:group_id => group.id, :group_membership_state_id => GroupMembershipState::ENROLLED, :count => 1, :info => info, :created_user_id => User::WEBSITE_ID, :updated_user_id => User::WEBSITE_ID)
                end
              else
                raise ApiErrorHandling::Exceptions::ResourceNotFoundException, I18n.t('api.not_found.group', :id => group_id)
              end
            end
          end
        rescue => e
          success = false
          exception = e
          person.notifications.destroy_all
          raise ActiveRecord::Rollback
        end
      end
    end
    NewRegistrationWorker.perform_async(person.id, group_membership.id) if person and group_membership

    return person, success, exception
  end

  private

  def international_vat_number
    'FI' + vat_number.gsub('-', '') unless vat_number.blank? or vat_number.index('FI') == 0
  end

  def vat_number_if_present
    unless vat_number.blank?
      vat_nro = vat_number
      # If VAT number doesn't start with two letters, let's format it as finnish vat-number
      unless vat_nro[0] =~ /[[:alpha:]]/ and vat_nro[1] =~ /[[:alpha:]]/
        vat_nro = international_vat_number
      end
      unless Valvat.new(vat_nro).valid?
        errors.add(:vat_number, I18n.t('errors.messages.invalid'))
      end
    end
    true
  end

end