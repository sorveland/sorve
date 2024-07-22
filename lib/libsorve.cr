require "http/server"
require "uri"
require "mime"
require "time"
require "toml"

module Sorve
  VERSION = "0.0.2"

  module Utils
    extend self

    ANSI_COLORS = {
      reset:  "\e[0m",
      red:    "\e[31m",
      green:  "\e[32m",
      yellow: "\e[33m",
      blue:   "\e[34m",
      magenta: "\e[35m",
      cyan:   "\e[36m",
    }

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

    def log_request(request, status_code, extra = "")
      status_color, status_suffix = case status_code
                                    when 200..299 then [ANSI_COLORS[:green], ""]
                                    when 300..399 then [ANSI_COLORS[:yellow], ""]
                                    when 400..499 then [ANSI_COLORS[:red], ""]
                                    when 500..599 then [ANSI_COLORS[:red], " ❌"]
                                    else               [ANSI_COLORS[:yellow], ""]
                                    end
      reset_color = ANSI_COLORS[:reset]
      status_text_str = status_text(status_code)
      timestamp = Time.local.to_s
      puts "#{ANSI_COLORS[:cyan]}[sorve::server INFO]#{reset_color} #{timestamp} - #{request.remote_address} - #{request.method} #{request.path} - #{status_color}#{status_code} #{status_text_str}#{status_suffix}#{reset_color}#{extra}"
    end

    def resolve_path(path)
      File.expand_path(path, Dir.current)
    end

    def format_duration(microseconds : Int64) : String
      case microseconds
      when 0..999 then "#{microseconds}μs"
      when 1_000..999_999 then "#{microseconds / 1000}ms"
      when 1_000_000..59_999_999 then "#{microseconds / 1_000_000}s"
      when 60_000_000..3_599_999_999 then "#{microseconds / 60_000_000}m"
      when 3_600_000_000..86_399_999_999 then "#{microseconds / 3_600_000_000}h"
      when 86_400_000_000..2_591_999_999_999 then "#{microseconds / 86_400_000_000}d"
      when 2_592_000_000_000..31_557_599_999_999 then "#{microseconds / 2_592_000_000_000}mo"
      else "#{microseconds / 31_557_600_000_000}y"
      end
    end

    def elapsed_time(since : Time)
      microseconds = (Time.local - since).total_microseconds.to_i64
      format_duration(microseconds)
    end
  end

  module Config
    extend self

    def load_config(config_path)
      if File.exists?(config_path)
        TOML.parse(File.read(config_path))
      else
        {} of String => TOML::Table
      end
    end

    def get_config_path(path)
      File.directory?(path) ? File.join(path, ".sorve.toml") : File.join(Dir.current, ".sorve.toml")
    end
  end

  module HTMLGenerator
    extend self

    def server_error(err : String | Nil)
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
            <footer>Served by <strong>Sorve #{VERSION}</strong></footer>
        </body>
        </html>
      EOF
    end

    def not_found_error
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
            <footer>Served by <strong>Sorve #{VERSION}</strong></footer>
        </body>
        </html>
      EOF
    end

    def list_directory(path : String, show_relative_path : Bool, request : HTTP::Request, root : String)
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
            <footer>Served by <strong>Sorve #{VERSION}</strong></footer>
        </body>
        </html>
      EOF
    end
  end
end
