require "option_parser"
require "http/server"
require "../../lib/libsorve"

@[Link("c")]
lib C
  # File operations
  fun open(file : ::Pointer(LibC::Char), oflag : LibC::Int, ...) : LibC::Int
  fun close(fd : Int32) : Int32
  fun read(fd : LibC::Int, buf : ::Pointer(Void), nbytes : LibC::SizeT) : LibC::SSizeT
  fun fstat(fd : LibC::Int, buf : ::Pointer(LibC::Stat)) : LibC::Int

  # Constants
  O_RDONLY = 0
  SEEK_SET = 0
end

module Sorve
  class Server

    {% if flag?(:linux) %}
      IS_LINUX = true
    {% else %}
      IS_LINUX = false
    {% end %}

    def self.run
      options = Hash(String, String | Int32).new

      OptionParser.parse do |parser|
        parser.banner = "Usage: sorve [options]"

        parser.on("-p PORT", "--port=PORT", "Port to listen on") { |port| options["port"] = port.to_i }
        parser.on("-d DIR", "--dir=DIR", "Directory to serve") { |dir| options["path"] = dir }
        parser.on("-h", "--help", "Show this help") do
          puts parser
          exit
        end
        parser.on("-v", "--version", "Show version") do
          puts "Sorve version #{VERSION}"
          exit
        end
      end

      options["path"] = Utils.resolve_path(options["path"]?.try(&.as(String)) || "./")

      config_path = Config.get_config_path(options["path"].as(String))
      config = Config.load_config(config_path)
      server_cfg = config["server"]

      port = options["port"]?.try(&.as(Int32)) || server_cfg["port"]?.try(&.as_i) || 3000
      base_path = Utils.resolve_path(server_cfg["path"]?.try(&.as_s) || options["path"].as(String))

      unless File.exists?(base_path)
        puts "Error: The specified path '#{base_path}' does not exist."
        puts "Please provide a valid directory or file path."
        exit(1)
      end

      show_relative_path = server_cfg["show_relative_path"]?.try(&.as_bool) || false

      server = HTTP::Server.new do |context|
        handle_request(context, base_path, show_relative_path, server_cfg)
      end

      address = server.bind_tcp("0.0.0.0", port)
      puts "Listening on http://#{address}, serving files from '#{base_path}'"
      server.listen
    end

    private def self.handle_request(context, base_path, show_relative_path, server_cfg)
      request_path = URI.decode(context.request.path[1..-1] || "")
      full_path = File.join(base_path, request_path)

      begin
        if File.directory?(full_path)
          serve_directory(context, full_path, show_relative_path, base_path)
        elsif File.file?(full_path)
          serve_file(context, full_path)
        else
          serve_not_found(context)
        end
      rescue e : Exception
        serve_error(context, e.message)
      end

      add_credits(context, server_cfg)
    end

    private def self.serve_directory(context, full_path, show_relative_path, base_path)
      context.response.content_type = "text/html"
      context.response.print HTMLGenerator.list_directory(full_path, show_relative_path, context.request, base_path)
      Utils.log_request(context.request, 200)
    end

    private def self.serve_file(context, full_path)
      if IS_LINUX
        serve_file_with_syscalls(context, full_path)
      else
        context.response.content_type = MIME.from_filename(full_path)
        context.response.print File.read(full_path)
        Utils.log_request(context.request, 200)
      end
    end

    private def self.serve_file_with_syscalls(context, full_path)
      path_cstr = full_path
      fd = C.open(path_cstr, C::O_RDONLY)
      if fd < 0
        puts "[sorve::fs] Failed to open file: #{full_path}"
        context.response.status_code = 500
        context.response.content_type = "text/plain"
        context.response.print "Internal Server Error"
        Utils.log_request(context.request, 500)
        return
      end

      stat = LibC::Stat.new
      if C.fstat(fd, pointerof(stat)) < 0
        puts "[sorve::fs] Failed to get file status for: #{full_path}"
        context.response.status_code = 500
        context.response.content_type = "text/plain"
        context.response.print "Internal Server Error"
        C.close(fd)
        Utils.log_request(context.request, 500)
        return
      end

      buffer = libc_read_file(fd, stat.st_size)
      context.response.content_type = MIME.from_filename(full_path)
      context.response.print buffer
      C.close(fd)
      Utils.log_request(context.request, 200)
    rescue e : Exception
      context.response.content_type = "text/plain"
      context.response.print "Internal Server Error: #{e.message}"
      Utils.log_request(context.request, 500)
    end

    private def self.libc_read_file(fd : Int32, size : Int64) : String
      buffer = Pointer(UInt8).malloc(size)
      bytes_read = C.read(fd, buffer, size)
      if bytes_read < 0
        raise "Failed to read file"
      end

      String.new(buffer, bytes_read)
    end

    private def self.serve_not_found(context)
      context.response.status_code = 404
      context.response.content_type = "text/html"
      context.response.print HTMLGenerator.not_found_error
      Utils.log_request(context.request, 404)
    end

    private def self.serve_error(context, error_message)
      context.response.status_code = 500
      context.response.content_type = "text/html"
      context.response.print HTMLGenerator.server_error(error_message)
      Utils.log_request(context.request, 500)
    end

    private def self.add_credits(context, server_cfg)
      no_credits = server_cfg["no_credits"]?.try(&.as_bool) || false
      context.response.headers["X-Powered-By"] = "Sorve #{VERSION}" unless no_credits
    end
  end
end

# Run the server
Sorve::Server.run
