class Api::Feedback < Api::PersonTemplate

  attr_accessor :title, :feedback_text

  validates_presence_of :feedback_text

  def self.init(params, organization)
    data = self.new
    data = self.superclass.init(params, organization, data)

    data.title = params[:title].strip unless params[:title].blank?
    data.feedback_text = params[:feedback_text].strip unless params[:feedback_text].blank?

    data
  end

  def create_person_and_memberships
    success = true
    exception = nil
    person = nil
    user_id = User::WEBSITE_ID
    Person.transaction do
      if person = Person.create_from_data(self, user_id)
        if person.valid?
          begin
            unless self.feedback_text.blank?
              contact = Contact.new
              contact.organization_id = organization_id
              contact.start_moment = Time.now
              contact.contact_type_id = ContactType::FEEDBACK
              contact.contact_state_id = ContactState::RECEIVED
              contact.title = self.title.blank? ? ' ' : self.title
              contact.info = self.feedback_text
              contact.private = false
              contact.target_person_id = person.id
              contact.created_user_id = user_id
              contact.updated_user_id = user_id

              if contact.save
                contact.update_customer_count

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
            end
          rescue => e
            success = false
            exception = e
            person.notifications.destroy_all
            raise ActiveRecord::Rollback
          end
        end
      end
    end
    return person, success, exception
  end

end