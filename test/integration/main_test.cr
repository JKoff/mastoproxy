require "spec"
require "http/client"
require "json"
require "file_utils"
require "sqlite3"

require "../../src/database"
require "../../src/persistor"
require "../../src/webserver"

def write(test_port : Int, payload : NamedTuple)
  client = HTTP::Client.new("localhost", test_port)
  response = client.post("/record", body: payload.to_json, headers: HTTP::Headers{"Content-Type" => "application/json"})
end

describe "Server Integration Test" do
  test_db_path = Path["./test_data.sqlite3"]
  test_port = -1

  before_each do
    FileUtils.rm(test_db_path) if File.exists?(test_db_path)

    db = Database.new test_db_path
    db.setup

    persistor = Persistor.new test_db_path
    persistor.spawn

    test_port = 0  # leave port selection to the OS
    ws = WebServer.new test_db_path, persistor.persist_channel
    address = ws.spawn "127.0.0.1", test_port
    test_port = address.port

    sleep 0.1
  end

  after_each do
    FileUtils.rm(test_db_path) if File.exists?(test_db_path)
  end

  it "should handle POST request to /record" do
    client = HTTP::Client.new("localhost", test_port)
    
    payload = {
      session_id: "test_session",
      seq_id: 0,
      client_time_msec: 1234567890,
      buffer: [
        {
          type: "SessionInit",
          seq_id: 0,
          client_time_msec: 1234567890,
          payload: {
            build: 1,
            is_debug_build: false,
            static_memory_usage: 1000,
            static_memory_peak_usage: 2000,
            platform_name: "test_platform",
            mobile_model_name: "test_model",
            locale: "en-US"
          }
        }
      ]
    }.to_json

    response = client.post("/record", body: payload, headers: HTTP::Headers{"Content-Type" => "application/json"})
    
    response.status_code.should eq(200)
    response.body.should eq("{}")

    DB.open "sqlite3://#{test_db_path}" do |db|
      db.query_one("SELECT COUNT(*) FROM sessions", as: Int32).should eq(1)
      db.query_one("SELECT COUNT(*) FROM writes", as: Int32).should eq(1)
      db.query_one("SELECT COUNT(*) FROM events", as: Int32).should eq(1)
    end
  end

  it "should handle GET request to /N1wEqlYlnsMy6fCANbX4qg==" do
    write(test_port, {
      session_id: "test_session",
      seq_id: 0,
      client_time_msec: 1234567890,
      buffer: [
        {
          type: "SessionInit",
          seq_id: 123,
          client_time_msec: 1234567890,
          payload: {
            build: 1,
            is_debug_build: false,
            static_memory_usage: 1000,
            static_memory_peak_usage: 2000,
            platform_name: "test_platform",
            mobile_model_name: "test_model",
            locale: "en-US"
          }
        }
      ]
    })

    client = HTTP::Client.new("localhost", test_port)
    
    response = client.get("/N1wEqlYlnsMy6fCANbX4qg==")
    
    response.status_code.should eq(200)
    response.body.should contain("test_session")
    response.body.should contain("123")
  end

  it "should return 404 for unknown routes" do
    client = HTTP::Client.new("localhost", test_port)
    
    response = client.get("/unknown_route")
    
    response.status_code.should eq(404)
    response.body.should eq("Not Found")
  end
end
