class Api::Customer < Api::PersonTemplate

  validates_presence_of :first_name, :last_name, :email, :contact_method_id

  def find_or_create_person(fundraising_customer)
    success = true
    exception = nil
    person = nil
    Person.transaction do
      begin
        if person = Person.create_from_data(self, User::WEBSITE_ID)
          fundraising_customer.person_id = person.id
          fundraising_customer.customer_id = person.customer_id
          fundraising_customer.updated_user_id = User::WEBSITE_ID
          fundraising_customer.save!

          unless group_ids.blank?
            group_ids.each do |group_id|
              group = Group.of_organization(organization_id).find_by_id(group_id)
              if group
                existing_membership = GroupMembership.where(:group_id => group_id, :customer_id => person.customer_id).first
                unless existing_membership
                  person.customer.group_memberships.create!(:group_id => group.id, :group_membership_state_id => group.get_default_membership_state_id(contact_method_id), :count => 1, :created_user_id => User::WEBSITE_ID, :updated_user_id => User::WEBSITE_ID)
                end
              else
                raise ApiErrorHandling::Exceptions::ResourceNotFoundException, I18n.t('api.not_found.group', :id => group_id)
              end
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
    return person, success, exception
  end

end