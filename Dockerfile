# Use the official Crystal image as the base image
FROM 84codes/crystal:master-alpine-latest

# Set the working directory inside the container
WORKDIR /workspace

# Copy the current directory (which should contain your Crystal source files) into the container
COPY . /workspace

# Install necessary build dependencies
RUN apk update && apk add --no-cache build-base

# Create a directory for the build output
RUN mkdir -p /workspace/dist

# Detect the architecture and set it as an environment variable
RUN crystal build --release --verbose -O3 --single-module -t -s --threads $(nproc) --static --progress sorve/src/sorve.cr -o /workspace/dist/sorve-linux

# Specify the entry point (if required) or just set the default CMD to nothing
CMD []
