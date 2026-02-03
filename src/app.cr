require "json-schema"
require "option_parser"
require "./constants"

module App
  # Server defaults
  port = DEFAULT_PORT
  host = DEFAULT_HOST
  process_count = DEFAULT_PROCESS_COUNT
  data_path = DEFAULT_DATA_PATH
  matter_port = DEFAULT_MATTER_PORT
  bearer_token : String? = nil
  docs = nil
  docs_file = nil

  # Command line options
  OptionParser.parse(ARGV.dup) do |parser|
    parser.banner = "Usage: #{PROGRAM_NAME} [arguments]"

    # Standard spider-gazelle options
    parser.on("-b HOST", "--bind=HOST", "Specifies the server host") { |bind_host| host = bind_host }
    parser.on("-p PORT", "--port=PORT", "Specifies the server port") { |bind_port| port = bind_port.to_i }

    # Provider-specific options per spec
    parser.on("--http=HOST:PORT", "Binds the Admin API (e.g., 127.0.0.1:8080)") do |http|
      parts = http.split(":", 2)
      host = parts[0]
      port = parts[1].to_i if parts.size > 1
    end

    parser.on("--data=PATH", "Base directory for provider storage") do |path|
      data_path = path
    end

    parser.on("--matter-port=PORT", "Matter protocol port (default: ephemeral)") do |mport|
      matter_port = mport.to_i
    end

    parser.on("--bearer=TOKEN", "Enable bearer token authentication") do |token|
      bearer_token = token
    end

    parser.on("-w COUNT", "--workers=COUNT", "Specifies the number of processes to handle requests") do |workers|
      process_count = workers.to_i
    end

    parser.on("-r", "--routes", "List the application routes") do
      ActionController::Server.print_routes
      exit 0
    end

    parser.on("-v", "--version", "Display the application version") do
      puts "#{NAME} v#{VERSION}"
      exit 0
    end

    parser.on("-c URL", "--curl=URL", "Perform a basic health check by requesting the URL") do |url|
      begin
        response = HTTP::Client.get url
        exit 0 if (200..499).includes? response.status_code
        puts "health check failed, received response code #{response.status_code}"
        exit 1
      rescue error
        error.inspect_with_backtrace(STDOUT)
        exit 2
      end
    end

    parser.on("-d", "--docs", "Outputs OpenAPI documentation for this service") do
      docs = ActionController::OpenAPI.generate_open_api_docs(
        title: NAME,
        version: VERSION,
        description: "Matter Provider - bridges virtual devices to Matter protocol"
      ).to_yaml

      parser.on("-f FILE", "--file=FILE", "Save the docs to a file") do |file|
        docs_file = file
      end
    end

    parser.on("-h", "--help", "Show this help") do
      puts parser
      exit 0
    end
  end

  if docs
    File.write(docs_file.as(String), docs) if docs_file
    puts docs_file ? "OpenAPI written to: #{docs_file}" : docs
    exit 0
  end

  # Load the routes
  puts "Launching #{NAME} v#{VERSION}"
  puts "Data path: #{data_path}"
  puts "HTTP API: #{host}:#{port}"
  puts "Matter port: #{matter_port}"
  puts "Bearer auth: #{bearer_token ? "enabled" : "disabled"}"
end

# Requiring config here ensures that the option parser runs before
# attempting to connect to databases etc.
require "./config"

module App
  # Set bearer token if provided
  App.bearer_token = bearer_token

  # Record start time
  App.start_time = Time.utc

  # Create storage directory
  Dir.mkdir_p(data_path) unless Dir.exists?(data_path)

  # Initialize and start the Matter provider
  provider = Provider.new(data_path, matter_port)
  provider.start

  # Start HTTP server
  server = ActionController::Server.new(port, host)

  # Clustering using processes
  server.cluster(process_count, "-w", "--workers") if process_count != 1

  Process.on_terminate do
    puts "\n > terminating gracefully"
    provider.stop
    server.close
  end

  {% unless flag?(:win32) %}
    register_severity_switch_signals
  {% end %}

  # Start the server
  server.run do
    puts "Listening on #{server.print_addresses}"
    puts "Matter bridge started - ready for commissioning"
    puts "Pairing code: #{provider.bridge.setup_code}"
  end

  # Shutdown message
  puts "#{NAME} shutdown complete\n"
end
