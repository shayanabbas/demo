class Api::ExternalCustomer < Api::PersonTemplate

  def create_person
    success = true
    exception = nil
    person = nil
    user_id = User::WEBSITE_ID
    Person.transaction do
      if person = Person.create_from_data(self, user_id)
        begin

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