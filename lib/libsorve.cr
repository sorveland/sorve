require "http/server"
require "uri"
require "mime"
require "time"
require "toml"

module Sorve
  VERSION = "0.0.1"

  module Utils
    extend self

    def status_text(code)
      case code
      when 200 then "OK"
      when 301 then "Moved Permanently"
      when 302 then "Found"
      when 400 then "Bad Request"
      when 404 then "Not Found"
      when 500 then "Internal Server Error"
      else "Unknown Status"
      end
    end

    def relative_path(root : String, path : String) : String
      root = root.chomp("/") + "/"
      path.starts_with?(root) ? path.sub(root, "/") : path
    end

    def log_request(request, status_code)
      status_color, status_suffix = case status_code
                                    when 200..299 then ["\e[32m", ""]
                                    when 300..399 then ["\e[33m", ""]
                                    when 400..499 then ["\e[31m", ""]
                                    when 500..599 then ["\e[31m", " ❌"]
                                    else               ["\e[33m", ""]
                                    end
      reset_color = "\e[0m"
      status_text_str = status_text(status_code)
      timestamp = Time.local.to_s
      puts "#{timestamp} - #{request.remote_address} - #{request.method} #{request.path} - #{status_color}#{status_code} #{status_text_str}#{status_suffix}#{reset_color}"
    end

    def resolve_path(path)
      File.expand_path(path, Dir.current)
    end

    def format_duration(seconds : Int64) : String
      case seconds
      when 0..60 then "#{seconds}s"
      when 61..3600 then "#{seconds / 60}m"
      when 3601..86400 then "#{seconds / 3600}h"
      when 86401..2_592_000 then "#{seconds / 86400}d"
      when 2_592_001..31_557_600 then "#{seconds / 2_592_000}mo"
      else "#{seconds / 31_557_600}y"
      end
    end

    def elapsed_time
      seconds = (Time.local - START_TIME).to_i
      format_duration(seconds)
    end
  end

  module Config
    extend self

    def load_config(config_path)
      if File.exists?(config_path)
        TOML.parse(File.read(config_path))
      else
        raise "Unable to load config file .sorve.toml in #{config_path}"
      end
    end

    def get_config_path(path)
      File.directory?(path) ? File.join(path, ".sorve.toml") : File.join(Dir.current, ".sorve.toml")
    end
  end

  module HTMLGenerator
    extend self

    def server_error(err : String | Nil)
      elapsed = Utils.elapsed_time
      <<-EOF
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>500 Internal Server Error</title>
            <style>
                body {
                    font-family: Arial, sans-serif;
                    text-align: center;
                    padding: 50px;
                    background-color: #232634;
                    color: #c6d0f5;
                }
                h1 {
                    font-size: 60px;
                    margin: 0;
                    color: #e74c3c;
                }
                p {
                    font-size: 20px;
                    margin: 10px 0;
                }
                a {
                    color: #3498db;
                    text-decoration: none;
                }
                a:hover {
                    text-decoration: underline;
                }
                footer {
                    margin-top: 30px;
                    font-size: 14px;
                    color: #888;
                }
            </style>
        </head>
        <body>
            <h1>500</h1>
            <p>Internal Server Error</p>
            <p>Sorry, something went wrong on our end. Please try again later or <a href="/">return to the homepage</a>.</p>
            <p>#{err}</p>
            <footer>Served by <strong>Sorve #{VERSION}</strong> in #{elapsed}</footer>
        </body>
        </html>
      EOF
    end

    def not_found_error
      elapsed = Utils.elapsed_time
      <<-EOF
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>404 Not Found</title>
            <style>
                body {
                    font-family: 'Comic Sans MS', cursive, sans-serif;
                    text-align: center;
                    padding: 50px;
                    background-color: #232634;
                    color: #c6d0f5;
                }
                h1 {
                    font-size: 80px;
                    color: #e74c3c;
                }
                p {
                    font-size: 24px;
                    margin: 20px 0;
                }
                a {
                    color: #3498db;
                    text-decoration: none;
                    font-weight: bold;
                }
                a:hover {
                    text-decoration: underline;
                }
                img {
                    max-width: 100%;
                    height: auto;
                }
                footer {
                    margin-top: 30px;
                    font-size: 14px;
                    color: #888;
                }
            </style>
        </head>
        <body>
            <h1>404</h1>
            <p>Oops! The page you're looking for doesn't exist.</p>
            <p>Maybe you got lost in the void? <a href="/">Return to the homepage</a></p>
            <img src="https://media.giphy.com/media/26ufm5b9KcsRzX8OW/giphy.gif" alt="Lost in Space">
            <footer>Served by <strong>Sorve #{VERSION}</strong> in #{elapsed}</footer>
        </body>
        </html>
      EOF
    end

    def list_directory(path : String, show_relative_path : Bool, request : HTTP::Request, root : String)
      elapsed = Utils.elapsed_time
      base_path = show_relative_path ? Utils.relative_path(root, path) : path
      content = Dir.children(path).map do |entry|
        full_path = File.join(path, entry)
        relative_path = entry
        relative_path += "/" if File.directory?(full_path)
        "<li><a href=\"#{request.path + relative_path}\">#{request.path + relative_path}</a></li>"
      end.join("\n")

      <<-EOF
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Index of #{base_path}</title>
            <style>
                body {
                    font-family: Arial, sans-serif;
                    text-align: center;
                    padding: 50px;
                    background-color: #232634;
                    color: #c6d0f5;
                }
                h1 {
                    font-size: 60px;
                    color: #3498db;
                }
                ul {
                    list-style-type: none;
                    padding: 0;
                    margin: 20px 0;
                }
                li {
                    margin: 10px 0;
                    font-size: 20px;
                }
                a {
                    color: #3498db;
                    text-decoration: none;
                }
                a:hover {
                    text-decoration: underline;
                }
                footer {
                    margin-top: 30px;
                    font-size: 14px;
                    color: #888;
                }
            </style>
        </head>
        <body>
            <h1>Index of #{base_path}</h1>
            <ul>
              #{content}
            </ul>
            <footer>Served by <strong>Sorve #{VERSION}</strong> in #{elapsed}</footer>
        </body>
        </html>
      EOF
    end
  end
end

# Set the server start time
START_TIME = Time.local
