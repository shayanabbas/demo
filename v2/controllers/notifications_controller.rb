module Api
  module V2
    class NotificationsController < Api::V2::ApiController

      before_action :set_notification, :only => [:mark_as_seen]

      def index
        raise ApiErrorHandling::Exceptions::AclException, "Unauthorized" unless can_read_notifications?
        notifications = nil
        begin
          if notifications = Notification.all.of_organization(current_api_organization.id).not_own(current_user.id).order('created_at DESC').limit(Notification::DEFAULT_DISPLAY_COUNT)
            notifications.add_to_set(:seen_by => current_person.id)
          end
        rescue => e
          Rails.logger.error e.to_s
        end
        respond_with(notifications)
      end

      def mark_as_seen
        @notification.add_to_set(:seen_by => current_person.id)
        render json: { :status => :ok }
      end

      private

      def set_notification
        @notification = Notification.find(params[:id])
      end

    end
  end
end