class Api::NewsletterOrder < Api::PersonTemplate

  def create_person_and_memberships
    success = true
    exception = nil
    person = nil
    user_id = User::WEBSITE_ID
    Person.transaction do
      if person = Person.create_from_data(self, user_id)
        begin
          unless group_ids.blank?
            group_ids.each do |group_id|
              group = Group.of_organization(organization_id).find_by_id(group_id)
              if group
                membership = GroupMembership.where(:group_id => group_id).where(:customer_id => person.customer_id).first
                membership_state_id = (self.group_membership_state_id.nil? ? group.get_default_membership_state_id(self.contact_method_id) : self.group_membership_state_id)
                person.customer.group_memberships.create!(:group_id => group.id, :group_membership_state_id => membership_state_id, :count => 1, :created_user_id => user_id, :updated_user_id => user_id) unless membership
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
    return person, success, exception
  end

end