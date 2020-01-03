class Api::Donation
  include ActiveModel::Validations
  include ActiveModel::Conversion
  extend ActiveModel::Naming

  attr_accessor :first_name, :last_name, :address, :zip, :city, :phone, :birth_year, :email, :contact_method_id, :amount, :bank, :language_id, :due_date, :locale, :organization_id, :no_marketing, :service_id, :product_id, :invoice_type_id, :group_ids, :consents, :client_ip_address

  MIN_MONTHLY_DONATION = 10
  MAX_MONTHLY_DONATION = 1000

  MIN_ONE_TIME_DONATION = 5
  MAX_ONE_TIME_DONATION = 20000

  VALID_DUE_DATES = [5, 20]
  VALID_INVOICE_TYPES = [InvoiceType::ELECTRONIC_ID, InvoiceType::DIRECT_ID]
  BANKS = {
      4   => "aktia",
      8   => "danske_bank",
      31  => "handelsbanken",
      1   => "nordea",
      5   => "osuuspankki",
      470 => "pop",
      39  => "s_pankki",
      715 => "saastopankki",
      36  => "tapiola",
      6   => "alandsbanken"
  }

  validates_presence_of :amount, :bank, :due_date, :first_name, :last_name, :address, :zip, :city, :phone, :organization_id, :locale
  validates :amount, :numericality => { :greater_than_or_equal_to => MIN_ONE_TIME_DONATION, :less_than_or_equal_to => MAX_ONE_TIME_DONATION }
  validates :email,
            :email => true,
            :allow_blank => true
  validates_inclusion_of :due_date, :in => VALID_DUE_DATES
  validates_inclusion_of :invoice_type_id, :in => VALID_INVOICE_TYPES, :allow_blank => true

  def self.init(params, organization, locale = DEFAULT_LANGUAGE)
    data = self.new
    data.organization_id = organization.id

    data.first_name = params['first_name'].strip.capitalize unless params['first_name'].blank?
    data.last_name = params['last_name'].strip.capitalize unless params['last_name'].blank?
    unless params['address'].blank?
      address = params['address'].strip
      if address.index(' ')
        street_address = address.split(' ').first
        street_number = address.split(' ',2).last
        address = "#{street_address.capitalize} #{street_number}"
      end
      data.address = address
    end
    data.zip = params['zip'].strip unless params['zip'].blank?
    data.city = params['city'].strip.capitalize unless params['city'].blank?
    data.email = params['email'].strip unless params['email'].blank?
    data.phone = params['phone'].strip unless params['phone'].blank?

    data.amount = params['amount'].to_d.truncate(2).to_f unless params['amount'].blank?
    data.due_date = params['due_date'].to_i
    data.bank = params['bank'].to_i unless params['bank'].blank?
    data.invoice_type_id = (params['invoice_type_id'].blank? ? InvoiceType::ELECTRONIC_ID : params['invoice_type_id'].to_i)
    data.birth_year = params['birth_year']

    unless locale.blank?
      lang = Language.find_with_locale(locale)
      data.language_id = lang.id if lang
      data.locale = (Language::SUPPORTED_LOCALIZATIONS.include?(locale) ? locale : DEFAULT_LANGUAGE)
    end

    data.client_ip_address = params[:client_ip_address].strip unless params[:client_ip_address].blank?
    data.consents = []
    unless params['consents'].blank?
      params['consents'].each do |consent|
        data.consents << (consent.instance_of?(Fixnum) ? consent : consent['consent_text_id'].to_i)
      end
    end

    data.no_marketing = params['no_marketing'] == 'true'

    unless params['contact_method_id'].blank?
      if params['contact_method_id'].to_i == 0
        # if contact method zero has been selected, let's mark no marketing flag so that automatically created services (e.g. magazine) are not created
        data.no_marketing = true
      else
        data.contact_method_id = params['contact_method_id'].to_i
      end
    end

    if params['service_id'].blank?
      service = organization.get_default_monthly_donation_service
      data.service_id = service.id if service
    else
      data.service_id = params['service_id'].to_i
    end

    if params['product_id'].blank?
      data.product_id = service.product_id if service
    else
      data.product_id = params['product_id'].to_i
    end

    data.group_ids = []
    unless params['group_ids'].blank?
      params['group_ids'].each do |group|
        data.group_ids << (group.instance_of?(Fixnum) ? group : group['group_id'].to_i)
      end
    end

    data
  end

  def instructions
    organization = Organization.find_by_id(self.organization_id)
    I18n.with_locale(self.locale) do
      if invoice_type_id == InvoiceType::DIRECT_ID
        I18n.t('donations.direct_payment')
      else
        subdomain = (organization.subdomain.index('-') ? organization.subdomain[0,organization.subdomain.index('-')] : organization.subdomain)
        organization_name = I18n.t("donations.organization.#{subdomain}.name")
        product = I18n.t("donations.organization.#{subdomain}.product")
        numbers = I18n.t("donations.organization.#{subdomain}.number_fields")
        I18n.t("donations.e_invoicing_instructions.#{BANKS[self.bank]}_html", :name => organization_name, :product => product, :numbers => numbers)
      end
    end
  end

  def create_person_and_service_customer(channel_id = nil, user_id = User::CLARA_ID)
    success = true
    exception = nil
    person = nil
    Person.transaction do
      begin
        service = Service.of_organization(organization_id).find_by_id(self.service_id)
        raise ApiErrorHandling::Exceptions::ResourceNotFoundException, I18n.t('api.not_found.service', :id => self.service_id) unless service

        if product_id.blank?
          product_id = service.product_id
        else
          product = Product.of_organization(organization_id).find_by_id(self.product_id)
          raise ApiErrorHandling::Exceptions::ResourceNotFoundException, I18n.t('api.not_found.product', :id => self.product_id) unless product
          product_id = product.id
        end

        if person = Person.create_from_data(self, user_id)
          service_customer = ServiceCustomer.new(:customer_id => person.customer_id, :amount => amount, :service_id => service_id, :product_id => product_id, :invoice_type_id => invoice_type_id, :service_state_id => ServiceState::ACTIVE, :due_day_of_month => due_date, :started_at => Time.now, :channel_contact_method_id => channel_id, :contact_method_id => self.contact_method_id, :dont_automatically_add_service => person.no_marketing, :created_user_id => user_id, :updated_user_id => user_id)
          unless invoice_type_id.nil?
            service_customer.bank_account = person.customer.bank_accounts.active.first
          end
          service_customer.save!

          unless group_ids.blank?
            group_ids.each do |group_id|
              group = Group.of_organization(organization_id).find_by_id(group_id)
              if group
                membership = GroupMembership.where(:group_id => group_id).where(:customer_id => person.customer_id).first
                person.customer.group_memberships.create!(:group_id => group.id, :group_membership_state_id => group.get_default_membership_state_id(contact_method_id), :count => 1, :created_user_id => user_id, :updated_user_id => user_id) unless membership
              else
                raise ApiErrorHandling::Exceptions::ResourceNotFoundException, I18n.t('api.not_found.group', :id => group_id)
              end
            end
          end
        end
      rescue => e
        success = false
        exception = e
        person.notifications.destroy_all if person
        raise ActiveRecord::Rollback
      end
    end
    return person, success, exception
  end

  def send_instructions(customer_number, reference_number)
    DonationEmailWorker.perform_async(self.as_json, customer_number, reference_number, self.organization_id)
  end

end