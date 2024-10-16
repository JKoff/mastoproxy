require "option_parser"
require "http/server"
require "http/client"
require "json"

require "./database"
require "./persistor"
require "./webserver"

database_path = Path["./data.sqlite3"]
bind_address = "127.0.0.1"
bind_port = 0  # let the OS pick a port

OptionParser.parse do |parser|
  parser.on("-d PATH", "--data=PATH", "Database") { |d| database_path = Path[d] / "data.sqlite3" }
  parser.on("-h HOST", "--host=HOST", "Bind host") { |h| bind_address = h }
  parser.on("-p PORT", "--port=PORT", "Bind port") { |p| bind_port = p.to_i }
end

db = Database.new database_path
db.setup

persistor = Persistor.new database_path
persistor.spawn

ws = WebServer.new database_path, persistor.persist_channel
ws.spawn bind_address, bind_port

sleep
