# Sorve

Sorve is a lightweight, configurable static file server written in Crystal. It's designed to be easy to use and customize, making it ideal for local development or simple hosting needs.

## Version

Current version: 0.0.1

## Features

- Serve static files from a specified directory
- Directory listing
- Configurable through command-line options and a TOML configuration file
- Custom 404 and 500 error pages
- Logging of requests with color-coded status codes
- Option to show relative or absolute paths in directory listings
- MIME type detection for served files

## Prerequisites

- Crystal (version 1.0.0 or later recommended)

## Installation

1. Clone the repository:
   ```
   git clone https://github.com/sorveland/sorve.git
   cd sorve
   ```

2. Build the project:
   ```
   crystal build sorve/src/sorve.cr -O3 -o sorve
   ```

## Usage

Run Sorve from the command line:

```
./sorve [options]
```

### Command-line Options

- `-p PORT`, `--port=PORT`: Specify the port to listen on (default: 3000)
- `-d DIR`, `--dir=DIR`: Specify the directory to serve (default: current directory)
- `-h`, `--help`: Show help message
- `-v`, `--version`: Show version information

### Configuration File

Sorve can be configured using a `.sorve.toml` file in the directory being served. Here's an example configuration:

```toml
[server]
port = 8080
path = "/path/to/serve"
show_relative_path = true
no_credits = false
```

Configuration options:

- `port`: The port to listen on
- `path`: The directory to serve
- `show_relative_path`: Whether to show relative paths in directory listings
- `no_credits`: Whether to omit the "X-Powered-By" header

Command-line options take precedence over configuration file settings.

## Project Structure

```
sorve/
├── lib/
│   └── sorve.cr
├── src/
│   └── sorve.cr
└── README.md
```

- `lib/sorve.cr`: Contains the core functionality of Sorve, including utility functions, configuration handling, and HTML generation.
- `src/sorve.cr`: The main entry point of the application, responsible for setting up and running the server.

## Modules

### Utils

Provides utility functions for path handling, request logging, and status code text mapping.

### Config

Handles loading and parsing of the TOML configuration file.

### HTMLGenerator

Generates HTML for directory listings and error pages.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is open source and available under the [Mozilla Public License 2.0 (MPL-2.0)](LICENSE).

## Contact

If you have any questions or feedback, please open an issue on the [GitHub repository](https://github.com/sorveland/sorve).

---

Happy serving with Sorve!
