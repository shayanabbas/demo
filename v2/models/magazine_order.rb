class Api::MagazineOrder < Api::PersonTemplate

  validates_presence_of :first_name, :last_name, :contact_method_id, :service_id, :locale, :organization_id

  def create_person_and_service_customer(channel_id = nil)
    success = true
    exception = nil
    person = nil
    Person.transaction do
      if person = Person.create_from_data(self, User::WEBSITE_ID)
        begin
          unless service_id.nil?
            service = Service.of_organization(organization_id).find_by_id(service_id)
            if service
              existing_service = ServiceCustomer.where(:customer_id => person.customer_id, :service_id => service_id).first
              unless existing_service
                person.customer.service_customers.create(:service_id => service_id, :service_state_id => ServiceState::ACTIVE, :started_at => Time.now, :contact_method_id => contact_method_id, :channel_contact_method_id => channel_id, :created_user_id => User::WEBSITE_ID, :updated_user_id => User::WEBSITE_ID)
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
    return person, success, exception
  end

end