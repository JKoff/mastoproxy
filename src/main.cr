require "option_parser"
require "http/server"
require "http/client"
require "json"

source_url = ""
slug = ""
bind_address = "127.0.0.1"
bind_port = 8080
refresh_interval = 0
latest_data = ""

OptionParser.parse do |parser|
  parser.on("-u URL", "--url=URL", "Source URL") { |url| source_url = url }
  parser.on("-s SLUG", "--slug=SLUG", "Slug") { |s| slug = s }
  parser.on("-h HOST", "--host=HOST", "Bind host") { |h| bind_address = h }
  parser.on("-p PORT", "--port=PORT", "Bind port") { |p| bind_port = p.to_i }
  parser.on("-i INTERVAL", "--interval=INTERVAL", "Refresh interval in seconds") { |i| refresh_interval = i.to_i }
end

puts "Source URL: #{source_url}"
puts "Slug: #{slug}"
puts "Refresh interval: #{refresh_interval} seconds"

def fetch_data(url : String) : String
  response = HTTP::Client.get(url)
  if response.success?
    response.body
  else
    "Error fetching data: #{response.status_code}"
  end
end

spawn do
  loop do
    latest_data = fetch_data(source_url)
    puts "Data fetched at #{Time.local}"
    sleep refresh_interval
  end
end

server = HTTP::Server.new do |context|
  path = context.request.path
  path_segments = path.split("/").reject(&.empty?)

  if path_segments.first? == slug
    context.response.content_type = "application/json"
    context.response.print latest_data
  else
    context.response.status_code = 404
    context.response.print "Not Found"
  end
end
address = server.bind_tcp(Socket::IPAddress.new(bind_address, bind_port))
puts "Listening on http://#{address}"
server.listen
