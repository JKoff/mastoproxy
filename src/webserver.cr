require "json"

MIN_BUILD = 1
SECRET = "N1wEqlYlnsMy6fCANbX4qg=="

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
          context.response.headers["Access-Control-Allow-Methods"] = "GET, OPTIONS"
          context.response.headers["Access-Control-Allow-Headers"] = "Content-Type"
        elsif origin && origin.matches?(/^https?:\/\/[\w-]+\.tail6612c.ts.net:[\d]+$/)
          context.response.headers["Access-Control-Allow-Origin"] = origin
          context.response.headers["Access-Control-Allow-Methods"] = "GET, OPTIONS, POST"
          context.response.headers["Access-Control-Allow-Headers"] = "Content-Type"
        else
          context.response.headers["Access-Control-Allow-Origin"] = ""
          context.response.headers["Access-Control-Allow-Methods"] = "GET, OPTIONS"
        end

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
        elsif context.request.method == "POST" && path_segments.size == 2 && path_segments[0] == SECRET && path_segments[1] == "set_levels"
          body = context.request.body
          unless body.nil?
            begin
              DB.open "sqlite3://#{@database_path}" do |db|
                db.exec "replace into kvs values (?, ?)", "levels", body.gets_to_end
              end
            rescue e
              puts "Failed to write levels (#{e.message})"
            end
          end
          context.response.content_type = "application/json"
          context.response.print "{}"
        elsif context.request.method == "POST" && path_segments.size == 2 && path_segments[0] == SECRET && path_segments[1] == "rewrite"
          DB.open "sqlite3://#{@database_path}" do |db|
            db.exec "drop table if exists events"
            db.exec "drop table if exists sessions"
            db.exec "drop table if exists save_files"
          end
          db = Database.new database_path
          db.setup
          DB.open "sqlite3://#{@database_path}" do |db|
            db.query "select payload from writes" do |rs|
              rs.each do
                persist_channel.send rs.read(String)
              end
            end
          end
          context.response.content_type = "application/json"
          context.response.print "{}"
        elsif context.request.method == "POST" && path_segments.size == 2 && path_segments[0] == SECRET && path_segments[1] == "nuke"
          DB.open "sqlite3://#{@database_path}" do |db|
            db.exec "drop table if exists events"
            db.exec "drop table if exists sessions"
            db.exec "drop table if exists save_files"
            db.exec "drop table if exists writes"
          end
          db = Database.new database_path
          db.setup
          context.response.content_type = "application/json"
          context.response.print "{}"
        elsif context.request.method == "GET" && path_segments.first? == SECRET
          if path_segments.size == 1
            handle_get_index(context.request, context.response)
          elsif path_segments.size == 3 && path_segments[1] == "session"
            handle_get_session(context.request, context.response, path_segments[2])
          elsif path_segments.size == 3 && path_segments[1] == "event"
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
    response.content_type = "application/json"
    q = "
      select
        session_id,
        (select coalesce(sum(payload_size_bytes), 0) from writes where session_id = s.session_id),
        s.event_client_time_msec,
        s.log_sent_client_time_msec,
        build,
        is_debug_build,
        static_memory_usage,
        static_memory_peak_usage,
        platform_name,
        mobile_model_name,
        locale,
        (select max(w.write_server_time_msec) from writes w where w.session_id = s.session_id) as last_write_time_msec,
        json_group_array(e.seq_id) as event_ids,
        json_group_array(e.event_type) as event_types,
        json_group_array(e.level_id) as event_level_ids
      from sessions s
      left join events e using (session_id)
      where build >= ?
      group by session_id
    "
    save_files_query = "
      select save_file_id, string_agg(session_id, \",\"), max(version) from save_files group by save_file_id
    "
    DB.open "sqlite3://#{@database_path}" do |db|
      size_bytes = db.scalar "SELECT page_count * page_size FROM pragma_page_count(), pragma_page_size()"
      write_size_bytes = db.scalar "SELECT coalesce(sum(payload_size_bytes), 0) FROM writes"
      result = JSON.build do |json|
        json.object do
          json.field "database_physical_bytes", size_bytes.as(Int64)
          json.field "database_write_bytes", write_size_bytes.as(Int64)
          json.field "sessions" do
            db.query q, MIN_BUILD do |rs|
              json.array do
                rs.each do
                  json.object do
                    json.field "session_id", rs.read(String)
                    json.field "write_size_bytes", rs.read(Int)
                    json.field "event_client_time_msec", rs.read(Int)
                    json.field "log_sent_client_time_msec", rs.read(Int)
                    json.field "build", rs.read(Int)
                    json.field "is_debug_build", rs.read(String) == "1"
                    json.field "static_memory_usage", rs.read(Int)
                    json.field "static_memory_peak_usage", rs.read(Int)
                    json.field "platform_name", rs.read(String)
                    json.field "mobile_model_name", rs.read(String)
                    json.field "locale", rs.read(String)
                    json.field "last_write_time_msec", rs.read(Int64)
                    json.field "event_ids", rs.read(String)
                    json.field "event_types", rs.read(String)
                    json.field "event_level_ids", rs.read(String)
                    # json.field "event_ids" do
                    #   json.array do
                    #     event_ids_or_nil = rs.read(String?)
                    #     if !event_ids_or_nil.nil?
                    #       event_ids_or_nil.split(",").each do |event_id|
                    #         json.number event_id.to_i
                    #       end
                    #     end
                    #   end
                    # end
                    # json.field "event_types" do
                    #   json.array do
                    #     mx = rs.read(String?)
                    #     if !mx.nil?
                    #       mx.split(",").each do |x|
                    #         json.string x.to_s
                    #       end
                    #     end
                    #   end
                    # end
                    # json.field "event_level_ids" do
                    #   json.array do
                    #     mx = rs.read(String?)
                    #     if !mx.nil?
                    #       mx.split(",").each do |x|
                    #         json.number x.to_i
                    #       end
                    #     end
                    #   end
                    # end
                    # json.field "event_payloads", rs.read(String)
                  end
                end
              end
            end  # sessions query
          end  # json.field "sessions"
          json.field "save_files" do
            db.query save_files_query do |rs|
              json.array do
                rs.each do
                  json.object do
                    json.field "save_file_id", rs.read(String)
                    json.field "session_ids" do
                      json.array do
                        session_ids_or_nil = rs.read(String?)
                        if !session_ids_or_nil.nil?
                          session_ids_or_nil.split(",").each do |session_id|
                            json.string session_id.to_s
                          end
                        end
                      end
                    end
                    json.field "version", rs.read(Int)
                  end
                end
              end
            end  # save files query
          end  # json.field "save_files"
          json.field "levels", (db.scalar "select coalesce((select value from kvs where key = 'levels'), '{}')").as(String)
        end  # json.object
      end  # JSON.build
      response.print result
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

  def handle_get_event(request, response, event_id)
    response.content_type = "application/json"
    q = "
      select
        session_id,
        seq_id,
        event_client_time_msec,
        log_sent_client_time_msec,
        event_type,
        event,
        level_id
      from sessions
      where session_id = ?
    "
    DB.open "sqlite3://#{@database_path}" do |db|
      session_id,
      seq_id,
      event_client_time_msec,
      log_sent_client_time_msec,
      event_type,
      event,
      level_id = db.query_one q, session_id, as:{String, Int64, Int64, Int64, String, String, String}
      result = JSON.build do |json|
        json.object do
          json.field "session_id", session_id
          json.field "seq_id", seq_id
          json.field "event_client_time_msec", event_client_time_msec
          json.field "log_sent_client_time_msec", log_sent_client_time_msec
          json.field "event_type", event_type
          json.field "event", event
          json.field "level_id", level_id
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
