class Persistor
  def initialize(database_path : Path)
    @database_path = database_path
    @persist_channel = Channel(String).new(capacity=16)
  end

  def persist_channel
    @persist_channel
  end

  def spawn
    spawn do
      while true
        begin
          to_persist = @persist_channel.receive
          sync = JSON.parse to_persist
          events = sync["buffer"].as_a
          DB.open "sqlite3://#{@database_path}" do |db|
            db.exec "insert into writes values (?, ?, ?, ?)",
              sync["session_id"].as_s,
              sync["seq_id"].as_i,
              sync["client_time_msec"].as_i,
              to_persist.size()
            events.each do |event|
              payload = event["payload"]
              if event["type"].as_s == "Game.SaveFileId"
                db.exec "insert into save_files values (?, ?, ?)",
                  payload["save_file_id"].as_s,
                  sync["session_id"].as_s,
                  payload["version"].as_i
              end
              if event["type"].as_s == "SessionInit"
                db.exec "insert into sessions values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                  sync["session_id"].as_s,
                  event["client_time_msec"].as_i,
                  sync["client_time_msec"].as_i,
                  payload["build"].as_i,
                  payload["is_debug_build"].as_bool,
                  payload["static_memory_usage"].as_i,
                  payload["static_memory_peak_usage"].as_i,
                  payload["platform_name"].as_s,
                  payload["mobile_model_name"].as_s,
                  payload["locale"].as_s
              end
              db.exec "insert into events values (?, ?, ?, ?, ?, ?)",
                sync["session_id"].as_s,
                event["seq_id"].as_i,
                event["client_time_msec"].as_i,
                sync["client_time_msec"].as_i,
                event["type"].as_s,
                payload.to_s
            end
          end
        rescue e
          puts "Unexpected JSON to persist (#{e.message}): #{to_persist}"
        end
      end
    end
  end
end