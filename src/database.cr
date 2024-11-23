require "sqlite3"

class Database
  def initialize(path : Path)
    @path = path
  end

  def setup
    DB.open "sqlite3://#{@path}" do |db|
      db.exec "create table if not exists save_files (
        save_file_id text,
        session_id text,
        version int,
        primary key(save_file_id, session_id)
      )"
      db.exec "create table if not exists sessions (
        session_id text primary key,
        event_client_time_msec int,
        log_sent_client_time_msec int,
        build int,
        is_debug_build text,
        static_memory_usage int,
        static_memory_peak_usage int,
        platform_name text,
        mobile_model_name text,
        locale text
      )"
      db.exec "create table if not exists events (
        session_id text,
        seq_id int,
        event_client_time_msec int,
        log_sent_client_time_msec int,
        event_type text,
        event text,
        level_id text,  /* nullable */
        primary key(session_id, seq_id)
      )"
      db.exec "create table if not exists writes (
        session_id text,
        seq_id int,
        log_sent_client_time_msec int,
        payload_size_bytes int,
        write_server_time_msec int,
        payload text,
        primary key(session_id, seq_id)
      )"
      db.exec "create table if not exists kvs (
        key text primary key,
        value int
      )"
    end
  end
end
