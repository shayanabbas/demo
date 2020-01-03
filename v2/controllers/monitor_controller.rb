module Api
  module V2
    class MonitorController < Api::V2::ApiController

      skip_before_filter :restrict_access, :only => [:show]

      def show
        raise ApiErrorHandling::Exceptions::AuthenticationError, "Incorrect api key" unless params[:api_session_id] == MONITORS_API_KEY

        case params[:id]

          when Monitoring::PINGDOM

            statuses = []
            check_started = Time.now

            response = {}

            begin
              unless Monitoring.count > 0
                statuses << 'MySQL query failed'
              end
            rescue => e
              statuses << e.to_s
            end

            begin
              result = SearchableObject.count
              unless result > 0
                statuses << 'MongoDB count failed'
              end
            rescue => e
              statuses << e.to_s
            end

            begin
              test_key = "monitoring-test"
              m = Monitoring.first
              m.set_counter(test_key, 42)
              m.increase_counter(test_key)
              unless m.get_counter(test_key).to_i == 43
                statuses << 'Redis counter failed'
              end
            rescue => e
              statuses << e.to_s
            end

            status = statuses.blank? ? 'OK' : statuses.join(', ')
            check_ended = Time.now
            response_time = (1000 * (check_ended - check_started)).round(0)

            builder = Nokogiri::XML::Builder.new do |xml|
              xml.pingdom_http_custom_check {
                xml.status status
                xml.response_time response_time
              }
            end

            monit = Monitoring.find(Monitoring::PINGDOM_ID)
            monit.monitoring_checks.create(:status => status[0..254], :ip_address => request.remote_ip, :started_at => check_started, :ended_at => check_ended) if monit

            respond_to do |format|
              format.json { render :json => {:pingdom_http_custom_check => {:status => status, :response_time => response_time } } }
              format.xml  { render :xml  => builder.to_xml }
            end
          else
            raise ApiErrorHandling::Exceptions::ResourceNotFoundException, "Incorrect action"
        end
      end

    end
  end
end