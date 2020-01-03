module Api
  module V2
    class TasksController < Api::V2::ApiController

      skip_before_filter :restrict_access, :only => [:index, :register_to_task, :ask_for_more]
      skip_before_action :verify_authenticity_token, :only => [:register_to_task_via_volunteers_intranet, :register_to_task]
      before_action :handle_location_parameters, :only => [:index]
      before_action :validate_api_request, :only => [:open_for_volunteers_intranet, :done_for_volunteers_intranet, :done_for_user, :tasks_for_user, :register_to_task_via_volunteers_intranet, :register_to_task]
      before_action :set_user_from_params, :only => [:tasks_for_user, :open_for_volunteers_intranet, :register_to_task_via_volunteers_intranet]
      before_action :set_task, :only => [:show]

      RESULTS_PER_PAGE = 8
      MIN_REGISTRATION_DURATION = 3.seconds
      DEFAULT_MAX_DISTANCE = 30

      def index
        raise AuthenticationError, "Incorrect authentication credentials." if current_api_organization.nil?
        params.has_key?(:page) ? page = params[:page].to_i : page = 1
        @tasks = Task.search_tasks(params, current_api_organization.id)
        @tasks = @tasks.of_organization(current_api_organization.id)
        @tasks = @tasks.exclude_bundled_repetitions
        @tasks = @tasks.can_be_shown_without_login if current_user.nil?
        @tasks = @tasks.public_fields.open.with_registerable_task_jobs.order([:ongoing, :start_moment, :id]).paginate(:page => page, :per_page => RESULTS_PER_PAGE)
        is_last_page = @tasks.total_pages == @tasks.current_page

        registered_task_jobs = nil
        registered_task_jobs = current_user.registered_task_jobs.map(&:id).uniq unless current_user.nil?

        respond_with({ :tasks => @tasks, :registered_task_jobs => registered_task_jobs, :last_page => is_last_page }, :include => TaskJob.public_task_job_fields)
      end

      def show
        respond_with({ :task => @task, :registered_task_job_ids => current_user.registered_task_jobs.map(&:id) }, :include => TaskJob.public_task_job_fields)
      end

      def open_for_volunteers_intranet
        tasks = []
        if @user.present? and not current_api_organization.nil?
          registered_task_ids = @user.registered_task_jobs.map(&:task_id)
          @tasks = Task.select('tasks.id, tasks.title, public_info, start_moment, end_moment, ongoing, tasks.service_id, tasks.responsible_person_id, email_templates.default_task_signature as signature').joins(:service).joins('LEFT OUTER JOIN email_templates ON services.email_template_id = email_templates.id')
          @tasks = @tasks.of_organization(current_api_organization.id)
          @tasks = @tasks.exclude_bundled_repetitions
          @tasks = @tasks.exclude_services(params[:excluded_service_ids]) unless params[:excluded_service_ids].blank?
          @tasks = @tasks.open.with_registerable_task_jobs.order([:ongoing, :start_moment, :id])
          @tasks.each do |t|
            signature = view_context.print_taggable_content(t.signature, t.responsible) unless t.signature.blank?
            task = { :id => t.id, :title => t.title, :public_info => t.public_info, :start_moment => t.start_moment, :end_moment => t.end_moment, :ongoing => t.ongoing, :signature => signature, :registered => registered_task_ids.include?(t.id) }
            task[:task_jobs] = []
            t.task_jobs.each do |tj|
              task[:task_jobs] << { :id => tj.id, :task_state_id => tj.task_state_id }
            end
            tasks << task
          end
        end
        respond_with({:tasks => tasks})
      end

      def done_for_volunteers_intranet(limit = 100)
        done_tasks = []
        unless current_api_organization.nil?
          @tasks = Task.of_organization(current_api_organization.id)
          @tasks = @tasks.exclude_bundled_repetitions
          @tasks = @tasks.done.order('start_moment DESC').limit(limit)
          @tasks.each do |t|
            task = { :title => t.title, :public_info => t.public_info, :start_moment => t.start_moment, :end_moment => t.end_moment, :ongoing => t.ongoing }
            task[:task_jobs] = []
            t.task_jobs.each do |tj|
              first_name = ''
              unless tj.person_id.nil?
                p = Person.where(:id => tj.person_id).select(:first_name).first
                first_name = p.first_name unless p.nil?
              end
              task[:task_jobs] << { :id => tj.id, :first_name => first_name }
            end
            done_tasks << task
          end
        end
        respond_with({:tasks => done_tasks})
      end

      def done_for_user
        done_tasks = []
        unless current_api_organization.nil?
          @tasks = Task.of_organization(current_api_organization.id).for_person(current_person)
          @tasks = @tasks.exclude_bundled_repetitions
          @tasks = @tasks.done.order('start_moment DESC')
          @tasks.each do |t|
            task = { :id => t.id, :title => t.title, :public_info => t.public_info, :start_moment => t.start_moment, :end_moment => t.end_moment, :ongoing => t.ongoing, :html_fg_color_hex => t.service.service_area.html_fg_color_hex, :html_bg_color_hex => t.service.service_area.html_bg_color_hex }
            task[:task_jobs] = []
            t.task_jobs.each do |tj|
              task[:task_jobs] << { :id => tj.id, :first_name => tj.person.first_name }
            end
            done_tasks << task
          end
        end
        respond_with({:tasks => done_tasks})
      end

      def tasks_for_user
        @tasks = nil
        if @user.present? and not current_api_organization.nil?
          user_person = @user.person(current_api_organization.id)
          if user_person
            select_sql = 'tasks.id, tasks.title, tasks.public_info, tasks.start_moment, tasks.end_moment, tasks.ongoing, tasks.service_id, '
            select_sql << 'CASE WHEN companies.id IS NOT NULL THEN companies.name ELSE persons.first_name END as first_name, '
            select_sql << 'persons.last_name, '
            select_sql << 'CASE WHEN companies.id IS NOT NULL THEN companies.address ELSE persons.address END as customer_address, '
            select_sql << 'CASE WHEN companies.id IS NOT NULL THEN companies.zip ELSE persons.zip END as zip, '
            select_sql << 'CASE WHEN companies.id IS NOT NULL THEN companies.city ELSE persons.city END as city, '
            select_sql << 'CASE WHEN companies.id IS NOT NULL THEN companies.phone WHEN persons.phone_mobile <> "" THEN persons.phone_mobile ELSE persons.phone_home END as phone, '
            select_sql << 'service_areas.html_fg_color_hex, service_areas.html_bg_color_hex'
            @tasks = Task.select(select_sql)
            @tasks = @tasks.of_organization(current_api_organization.id)
            @tasks = @tasks.joins('LEFT JOIN persons ON persons.customer_id = tasks.customer_id')
            @tasks = @tasks.joins('LEFT JOIN companies ON companies.customer_id = tasks.customer_id')
            @tasks = @tasks.joins(:service).joins('INNER JOIN service_areas ON services.service_area_id = service_areas.id')
            @tasks = @tasks.where("EXISTS (SELECT 1 FROM task_jobs tj WHERE tj.task_id = tasks.id AND tj.person_id = #{user_person.id} AND tj.task_state_id = #{TaskState::ALLOCATED}) OR EXISTS (SELECT 1 FROM task_jobs tj INNER JOIN task_job_persons tjp ON tj.id = tjp.task_job_id AND tjp.person_id = #{user_person.id} AND tjp.allocated_at IS NOT NULL WHERE tj.task_id = tasks.id)")
            @tasks = @tasks.where('tasks.task_state_id IN (?)', [TaskState::IN_PROGRESS, TaskState::ALLOCATED]).where("tasks.start_moment > ? OR tasks.ongoing = true", Time.now).order(:start_moment)
          end
        end
        respond_with({:tasks => @tasks})
      end

      def register_to_task_via_volunteers_intranet
        handle_task_registration(params, @user)
      end

      def register_to_task
        handle_task_registration(params, current_user)
      end

      def register_to_task_without_account
        status = :ok
        if current_organization
          task = Task.find(params[:task_id])
          task_job = TaskJob.find(params[:task_job_id])
          raise ApiErrorHandling::Exceptions::ResourceNotFoundException, "no task found for id #{params[:task_id]}" unless task
          raise ApiErrorHandling::Exceptions::ResourceNotFoundException, "no task id #{params[:task_id]} found in organization" unless task.organization_id == current_organization.id
          raise ApiErrorHandling::Exceptions::ResourceNotFoundException, "no task job found for id #{params[:task_job_id]}" unless task_job
          raise ApiErrorHandling::Exceptions::MissingParametersError, "no person parameters provided." if params[:first_name].blank? and params[:last_name] and (params[:email].blank? or params[:phone].blank?)
          if not params[:company].blank? or (params[:duration].to_f / 1000 < MIN_REGISTRATION_DURATION)
            logger.info "Possible bot registration: #{params.inspect}. IP-address: #{request.remote_ip}"
          elsif task.registration_expired?
            status = :registration_expired
          elsif person = Person.find_registered_person(current_organization.id, params[:first_name], params[:last_name], params[:email], params[:phone], request.remote_ip)
            tji = task_job.task_job_person(person)
            unless tji
              tji = task_job.create_task_job_person(person.id)
            end
            unless tji.nil?
              if tji.register!(nil, params[:registering_message])
                task.notify_responsible_person(tji, current_user)
              else
                status = :already_allocated
              end
            end
          else
            status = :unauthorized
          end
        else
          status = :unauthorized
        end
        render json: { :status => status }
      end

      def ask_for_more
        status = :ok
        task = Task.find(params[:task_id])
        raise ApiErrorHandling::Exceptions::ResourceNotFoundException, "no task found for id #{params[:task_id]}" unless task
        raise ApiErrorHandling::Exceptions::UserIdentificationException, "no current user found" unless current_user
        question = params[:task_question]
        if question.length < 10
          status = :bad_request
        else
          task.send_question_to_responsible(question, current_user)
        end
        render json: { :status => status }
      end

      def handle_location_parameters
        if !params[:max_distance_in_kilometers].blank? && (params[:lat].blank? or params[:long].blank?)
          if current_person
            latitude, longitude = current_person.check_and_geocode_if_necessary!
            unless latitude.blank? or longitude.blank?
              params[:lat] = latitude
              params[:long] = longitude
            end
          elsif current_api_organization
            unless current_api_organization.latitude.blank? or current_api_organization.longitude.blank?
              params[:lat] = current_api_organization.latitude
              params[:long] = current_api_organization.longitude
            end
          end
        end
      end

      private

      def handle_task_registration(params, current_user)
        status = :ok
        task = Task.find(params[:id])
        task_job = TaskJob.find(params[:task_job_id])
        raise ApiErrorHandling::Exceptions::ResourceNotFoundException, "no task found for id #{params[:task_id]}" unless task
        raise ApiErrorHandling::Exceptions::ResourceNotFoundException, "no task job found for id #{params[:task_job_id]}" unless task_job
        raise ApiErrorHandling::Exceptions::UserIdentificationException, "no current user found" unless current_user
        if task.registration_expired?
          status = :registration_expired
        elsif person = current_user.person(task.organization_id)
          tji = task_job.task_job_person(person)
          unless tji
            tji = task_job.create_task_job_person(person.id)
          end
          unless tji.nil?
            if tji.register!(nil, params[:registering_message])
              task.notify_responsible_person(tji, current_user)
            else
              status = :already_allocated
            end
          end
        else
          status = :unauthorized
        end
        render json: { :status => status }
      end

      def set_task
        @task = Task.find_by_id(params[:id])
        raise ApiErrorHandling::Exceptions::ResourceNotFoundException, "no task found for id #{params[:id]}" unless @task
      end

    end
  end
end