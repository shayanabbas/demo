class Api::Fundraising
  include ActiveModel::Validations
  include ActiveModel::Conversion
  extend ActiveModel::Naming

  attr_accessor :organization_id, :first_name, :last_name, :address, :zip, :city, :email, :phone, :language_id, :fundraising_id, :fundraising_type_id, :fundraising_customer_state_id, :amount, :event_date, :payment_message, :message, :customer_reference, :contact_method_id, :results_info_contact_method_id, :external_link_url, :service_id, :company_name, :company_extension, :vat_number, :intermediator_id, :einvoicing_address, :anonymous, :only_service, :group_ids, :consents, :client_ip_address

  validates_presence_of :fundraising_type_id, :organization_id
  validates_presence_of :first_name, :last_name, :unless => lambda{ |f| f.anonymous }
  validates_presence_of :company_name, :if => lambda{ |f| [FundraisingType::COLLABORATION, FundraisingType::CORPORATE_DONATION, FundraisingType::DAY_JOB_COLLECTION].include?(f.fundraising_type_id) }
  validates_presence_of :fundraising_id, :amount, :if => lambda{ |f| f.fundraising_type_id == FundraisingType::ONE_TIME_DONATION }
  validates_presence_of :event_date, :payment_message, :if => lambda{ |f| [FundraisingType::ANNIVERSARY_COLLECTION, FundraisingType::MEMORIAL_COLLECTION].include?(f.fundraising_type_id) }
  validates :email, :email => true, :if => :contact_method_email?
  validates_presence_of :address, :zip, :city, :if => :contact_method_post?
  validates_inclusion_of :fundraising_type_id, :in => FundraisingType.select(:id).map(&:id)
  validates_inclusion_of :fundraising_customer_state_id, :in => [FundraisingCustomerState::CONFIRMED, FundraisingCustomerState::PAID], :allow_blank => true
  validates_inclusion_of :results_info_contact_method_id, :in => ContactMethod::fundraising_results.select(:id).map(&:id), :allow_blank => true

  validates_inclusion_of :intermediator_id, :in => Intermediator.select(:id).map(&:id), :allow_blank => true
  validates_presence_of :einvoicing_address, :if => lambda{ |f| !f.intermediator_id.blank? }

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

    unless locale.blank?
      lang = Language.find_with_locale(locale)
      data.language_id = lang.id if lang
    end

    data.fundraising_id = params[:fundraising_id].to_i unless params[:fundraising_id].blank?
    data.fundraising_type_id = params[:fundraising_type_id].to_i unless params[:fundraising_type_id].blank?
    data.fundraising_customer_state_id = params[:fundraising_customer_state_id].to_i unless params[:fundraising_customer_state_id].blank?

    data.intermediator_id = params[:intermediator_id].to_i unless params[:intermediator_id].blank?
    data.einvoicing_address = params[:einvoicing_address] unless params[:einvoicing_address].blank?

    data.amount = params[:amount].to_d.truncate(2).to_f unless params[:amount].blank?
    data.event_date = params[:event_date]
    data.payment_message = params[:payment_message].strip unless params[:payment_message].blank?
    data.message = params[:message].strip unless params[:message].blank?
    data.customer_reference = params[:customer_reference].strip unless params[:customer_reference].blank?
    data.contact_method_id = params[:contact_method_id].to_i unless params[:contact_method_id].blank?
    data.results_info_contact_method_id = params[:results_info_contact_method_id].to_i unless params[:results_info_contact_method_id].blank?
    data.external_link_url = params[:external_link_url].strip unless params[:external_link_url].blank?
    data.service_id = params[:service_id].to_i unless params[:service_id].blank?

    data.company_name = params[:company_name].strip unless params[:company_name].blank?
    data.company_extension = params[:company_extension].strip unless params[:company_extension].blank?
    data.vat_number = params[:vat_number].strip unless params[:vat_number].blank?

    data.anonymous = (params[:anonymous].blank? ? false : params[:anonymous].to_i == 1)
    data.only_service = (params[:only_service].blank? ? false : params[:only_service].to_i == 1)

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

  def create_person_and_fundraising
    success = true
    exception = nil
    person = nil
    fundraising = nil
    fundraising_customer = nil
    company = nil
    Person.transaction do

      if self.anonymous
        organization = Organization.find_by_id(self.organization_id)
        unless organization.nil?
          unless person = organization.donation_anonymous_person
            raise ApiErrorHandling::Exceptions::ResourceNotFoundException, I18n.t('api.not_found.anonymous')
          end
        end
      else
        person = Person.create_from_data(self, User::WEBSITE_ID)
      end

      if person
        begin
          if (day_job_collection? or collaboration? or corporate_donation?) && !company_name.blank?
            if company = Company.create_from_data(self, User::WEBSITE_ID, CompanyType::BENEFACTOR)
              person.employer_company_id = company.id
              person.person_type_id = PersonType::CONTACT_PERSON_ID
              person.save
            end
          end

          unless only_service
            if fundraising_id.blank?
              title = company.nil? ? "#{self.first_name} #{self.last_name}" : company.search_name
              title = title[0..49] unless title.blank?

              fundraising = ActiveRecord::Base::Fundraising.create!(
                :organization_id => self.organization_id,
                :fundraising_type_id => self.fundraising_type_id,
                :title => title,
                :event_date => self.event_date,
                :payment_message => (self.payment_message.blank? ? nil : self.payment_message[0..99]),
                :results_info_contact_method_id => self.results_info_contact_method_id,
                :info => self.message,
                :external_link_url => (self.external_link_url.blank? ? nil : self.external_link_url[0..999]),
                :passivated => false,
                :created_user_id => User::WEBSITE_ID,
                :updated_user_id => User::WEBSITE_ID
              )
            else
              fundraising = ActiveRecord::Base::Fundraising.of_organization(organization_id).find_by_id(fundraising_id)
              unless fundraising
                raise ApiErrorHandling::Exceptions::ResourceNotFoundException, I18n.t('api.not_found.fundraising', :id => fundraising_id)
              end
            end

            if fundraising
              if fundraising_customer_state_id.blank?
                if one_time_donation?
                  self.fundraising_customer_state_id = FundraisingCustomerState::PAID       # one time donations are always paid
                else
                  self.fundraising_customer_state_id = FundraisingCustomerState::CONFIRMED  # otherwise the fundraising is confirmed and invoiced later
                end
              end

              fundraising_customer = fundraising.fundraising_customers.new(
                :person_id => person.id,
                :fundraising_customer_state_id => self.fundraising_customer_state_id,
                :created_user_id => User::WEBSITE_ID,
                :updated_user_id => User::WEBSITE_ID
              )
              if (day_job_collection? or collaboration? or corporate_donation?) && company
                fundraising_customer.customer_id = company.customer_id
                fundraising_customer.company_id = company.id
              else
                fundraising_customer.customer_id = person.customer_id
              end
              if !self.amount.nil? && self.amount > 0
                fundraising_customer.amount = 1
                fundraising_customer.unit_price = self.amount
                fundraising_customer.total_amount = self.amount
              end
              if one_time_donation? or collaboration? or corporate_donation?
                fundraising_customer.info = self.message
              end
              fundraising_customer.customer_reference = self.customer_reference
              fundraising_customer.save!
            end
          end

          unless group_ids.blank?
            group_ids.each do |group_id|
              group = Group.of_organization(organization_id).find_by_id(group_id)
              if group
                existing_membership = GroupMembership.where(:group_id => group_id, :customer_id => person.customer_id).first
                unless existing_membership
                  if testament? && !self.message.blank?
                    info = self.message[0..199]  # group_memberships.info max length is 200
                  end
                  person.customer.group_memberships.create!(:group_id => group.id, :group_membership_state_id => group.get_default_membership_state_id(contact_method_id), :count => 1, :info => info, :created_user_id => User::WEBSITE_ID, :updated_user_id => User::WEBSITE_ID)
                end
              else
                raise ApiErrorHandling::Exceptions::ResourceNotFoundException, I18n.t('api.not_found.group', :id => group_id)
              end
            end
          end

          unless service_id.nil?
            service = Service.of_organization(organization_id).find_by_id(service_id)
            if service
              existing_service = ServiceCustomer.where(:customer_id => person.customer_id, :service_id => service_id).first
              unless existing_service
                person.customer.service_customers.create(:service_id => service_id, :service_state_id => ServiceState::ACTIVE, :started_at => Time.now, :info => self.message, :created_user_id => User::WEBSITE_ID, :updated_user_id => User::WEBSITE_ID)
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

    NewFundraisingWorker.perform_async(fundraising.id, fundraising_customer.id) if fundraising && fundraising_customer

    return person, fundraising_customer, success, exception
  end

  private

  def international_vat_number
    'FI' + vat_number.gsub('-', '') unless vat_number.blank? or vat_number.index('FI') == 0
  end

  def vat_number_if_present
    if not vat_number.blank?
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

  def contact_method_email?
    contact_method_id == ContactMethod::EMAIL
  end

  def contact_method_post?
    contact_method_id == ContactMethod::POST
  end

  def one_time_donation?
    fundraising_type_id == FundraisingType::ONE_TIME_DONATION
  end

  def day_job_collection?
    fundraising_type_id == FundraisingType::DAY_JOB_COLLECTION
  end

  def collaboration?
    fundraising_type_id == FundraisingType::COLLABORATION
  end

  def corporate_donation?
    fundraising_type_id == FundraisingType::CORPORATE_DONATION
  end

  def testament?
    fundraising_type_id == FundraisingType::TESTAMENT
  end

  def intangible_gift?
    fundraising_type_id == FundraisingType::INTANGIBLE_GIFT
  end

end