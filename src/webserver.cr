require "json"

MIN_BUILD = 1

class WebServer
  def initialize(database_path : Path, persist_channel : Channel)
    @database_path = database_path
    @server = HTTP::Server.new do |context|
      begin
        path = context.request.path
        path_segments = path.split("/").reject(&.empty?)

        origin = context.request.headers["Origin"]?
        if origin && origin.matches?(/^https?:\/\/[\w-]+\.itch\.zone$/)
          context.response.headers["Access-Control-Allow-Origin"] = origin
        else
          context.response.headers["Access-Control-Allow-Origin"] = "https://itch.zone"
        end
        context.response.headers["Access-Control-Allow-Methods"] = "GET, OPTIONS"
        context.response.headers["Access-Control-Allow-Headers"] = "Content-Type"

        if context.request.method == "OPTIONS"
          context.response.status_code = 204
          context.response.headers["Access-Control-Max-Age"] = "86400" # 24 hours
          context.response.print ""
        elsif context.request.method == "POST" && path_segments.first? == "record"
          body = context.request.body
          unless body.nil?
            persist_channel.send body.gets_to_end
          end
          context.response.content_type = "application/json"
          context.response.print "{}"
        elsif context.request.method == "GET" && path_segments.first? == "N1wEqlYlnsMy6fCANbX4qg=="
          if path_segments.size == 1
            handle_get_index(context.request, context.response)
          elsif path_segments.size == 3 && path_segments[1] == "session"
            handle_get_session(context.request, context.response, path_segments[2])
          end
        else
          context.response.status_code = 404
          context.response.print "Not Found"
        end
      rescue e
        context.response.status_code = 500
        puts "Error: #{e.message}"
        context.response.print "Error: #{e.message}"
      end
    end
  end

  def handle_get_index(request, response)
    response.content_type = "text/html"
    q = "
      select
        session_id,
        (select coalesce(sum(payload_size_bytes), 0) from writes where session_id = sessions.session_id)
      from sessions
      where build >= ?
    "
    DB.open "sqlite3://#{@database_path}" do |db|
      size_bytes = db.scalar "SELECT page_count * page_size FROM pragma_page_count(), pragma_page_size()"
      write_size_bytes = db.scalar "SELECT coalesce(sum(payload_size_bytes), 0) FROM writes"
      response.print "<p>Database is #{size_bytes.as(Int64).humanize_bytes} physical, #{write_size_bytes.as(Int64).humanize_bytes} total writes.</p>"
      response.print "<table>"
      db.query q, MIN_BUILD do |rs|
        response.print "
          <tr>
            <th>#{rs.column_name(0)}</th>
            <th>Total size of writes</th>
          </tr>"
        rs.each do
          session_id = rs.read(String)
          session_size_bytes = rs.read(Int)
          response.print "
            <tr>
              <td><a href=\"#\">#{session_id}</a></td>
              <td>#{session_size_bytes.humanize_bytes}</td>
            </tr>"
        end
      end
      response.print "</table>"
    end
  end

  def handle_get_session(request, response, session_id)
    response.content_type = "application/json"
    q = "
      select
        event_client_time_msec,
        log_sent_client_time_msec,
        build,
        is_debug_build,
        static_memory_usage,
        static_memory_peak_usage,
        platform_name,
        mobile_model_name,
        locale,
        (select coalesce(sum(payload_size_bytes), 0) from writes where session_id = sessions.session_id) as write_size_bytes
      from sessions
      where session_id = ?
    "
    DB.open "sqlite3://#{@database_path}" do |db|
      event_client_time_msec,
      log_sent_client_time_msec,
      build,
      is_debug_build,
      static_memory_usage,
      static_memory_peak_usage,
      platform_name,
      mobile_model_name,
      locale,
      write_size_bytes = db.query_one q, session_id, as:{Int64, Int64, Int64, String, Int64, Int64, String, String, String, Int64}
      result = JSON.build do |json|
        json.object do
          json.field "event_client_time_msec", event_client_time_msec
          json.field "log_sent_client_time_msec", log_sent_client_time_msec
          json.field "build", build
          json.field "is_debug_build", is_debug_build
          json.field "static_memory_usage", static_memory_usage
          json.field "static_memory_peak_usage", static_memory_peak_usage
          json.field "platform_name", platform_name
          json.field "mobile_model_name", mobile_model_name
          json.field "locale", locale
          json.field "write_size_byte", write_size_bytes
        end
      end
      response.print result
    end
  end

  def spawn(bind_address : String, bind_port : Int)
    address = @server.bind_tcp(Socket::IPAddress.new(bind_address, bind_port))
    puts "Listening on http://#{address}"
    spawn do
      @server.listen
    end
    address
  end
end
