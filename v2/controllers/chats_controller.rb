module Api
  module V2
    class ChatsController < Api::V2::ApiController

      before_action :set_chat, :only => [:messages, :insert_message, :update, :add_new_participant, :mark_as_seen, :remove_participant]
      before_action :set_one_to_one_chat_by_participants, :only => [:get_chat_identifier]
      before_action :authorize_current_person, :only => [:messages, :insert_message, :update, :add_new_participant, :remove_participant]

      def messages
        offset = params[:offset].blank? ? 0 : params[:offset].to_i
        end_offset = offset + Chat::MAXIMUM_PRINTED_MESSAGES
        end_offset = @chat.messages.size if @chat.messages.size < end_offset
        messages = @chat.ordered_messages(offset, end_offset)
        @chat.mark_unseen_as_seen(current_chat_person)
        participants = nil
        participants = @chat.participants(current_chat_person.id) if offset == 0

        respond_with(:messages => messages, :participants => participants, :server_time => (Time.now.to_i * 1000))
      end

      def create
        if not params[:participant_person_ids].blank? and not current_person.nil? and params[:participant_person_ids].include?(current_person.id.to_s)
          if chat = Chat.create_new_chat(params[:participant_person_ids], current_person, nil, Chat::ONE_TO_ONE)
            chat.insert_message(current_person, params[:message])
          end
        else
          raise ApiErrorHandling::Exceptions::AclException, "unauthorized action"
        end
        render json: { :id => chat.id.to_s, :participants => chat.participants(current_person.id) }
      end

      def update
        if @chat.update(:title => params[:title])
          @chat.insert_message(current_person, params[:title], message_type = ChatMessage::TITLE_CHANGED)
        else
          raise ApiErrorHandling::Exceptions::MissingParametersError, "couldn't update chat with parameters #{params}"
        end
        render json: { :status => :ok }
      end

      def insert_message
        unless @chat.nil?
          if params[:message].blank? or !@chat.insert_message(current_chat_person, params[:message])
            raise ApiErrorHandling::Exceptions::MissingParametersError, "couldn't insert new message with #{current_chat_person.id} and #{params[:message]}"
          end
        else
          if @chat = Chat.create_new_chat(params[:participant_person_ids], current_person)
            @chat.insert_message(current_person, params[:message])
          end
        end
        render json: { :participants => @chat.participants(current_chat_person.id) }
      end

      def add_new_participant
        if participant = Person.find(params[:person_id])
          @chat.add_participant(params[:person_id])
          @chat.insert_message(participant, params[:person_id].to_i, message_type = ChatMessage::PERSON_ADDED)
        else
          raise ApiErrorHandling::Exceptions::MissingParametersError, "couldn't insert new participant with person id #{params[:person_id]}"
        end
        render json: { :participant_person_ids => @chat.participant_person_ids, :participants => @chat.participants(current_person.id) }
      end

      def remove_participant
        raise ApiErrorHandling::Exceptions::AclException, "unauthorized action" unless params[:person_id].to_i == current_person.id
        unless @chat.remove_participant(params[:person_id])
          raise ApiErrorHandling::Exceptions::MissingParametersError, "couldn't remove participant with person id #{params[:person_id]}"
        else
          @chat.insert_message(current_person, params[:person_id].to_i, message_type = ChatMessage::PERSON_LEFT)
        end
        render json: { :status => :ok }
      end

      def mark_as_seen
        @chat.mark_unseen_as_seen(current_chat_person)
        render json: { :status => :ok }
      end

      def get_chat_identifier
        identifier = nil
        identifier = @chat.id.to_s unless @chat.nil?
        render json: { :id => identifier }
      end

      private

      def set_chat
        raise ApiErrorHandling::Exceptions::MissingParametersError, "no chat id provided" if params[:id].blank?
        begin
          @chat = Chat.find(params[:id])
        rescue Mongoid::Errors::DocumentNotFound => e
          Rails.logger.error e.to_s
          raise ApiErrorHandling::Exceptions::MissingParametersError, "no chat found - maybe it was removed?"
        end
      end

      def set_one_to_one_chat_by_participants
        raise ApiErrorHandling::Exceptions::MissingParametersError, "no participant_person_ids provided" if params[:participant_person_ids].blank?
        @chat = Chat.find_by_participants(params[:participant_person_ids])
      end

      def authorize_current_person
        authorized = false
        authorized = true if @chat.authorized_for_person?(current_chat_person, can_access_intranet?)
        raise ApiErrorHandling::Exceptions::AclException, "unauthorized action" unless authorized
      end

      def current_chat_person
        current_person.present? ? current_person : current_video_conference_person
      end

    end
  end
end