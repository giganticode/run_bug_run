require 'json'
require 'zlib'

module RunBugRun
  module JSONUtils

    def decompress(io, compression, &block)
      case compression
      when :gzip
        Zlib::GzipReader.wrap(io, &block)
      when :none
        block[io]
      else
        raise ArgumentError, 'invalid compression'
      end
    end

    def read_jsonl(io, compression:, symbolize_names: true, **kwargs)
      decompress(io, compression) do |decompressed_io|
        decompressed_io.each_line.map do |line|
          JSON.parse(line, symbolize_names:, **kwargs)
        end
      end
    end

    def read_json(io, compression:, symbolize_names: true, **kwargs)
      decompress(io, compression) do |decompressed_io|
        JSON.parse(decompressed_io.read, symbolize_names:, **kwargs)
      end
    end

    def read(filename, symbolize_names: true, **kwargs)
      File.open(filename) do |io|
        case filename.to_s
        when /\.jsonl$/
          read_jsonl(io, symbolize_names:, compression: :none, **kwargs)
        when /\.jsonl\.gz$/
          read_jsonl(io, symbolize_names:, compression: :gzip, **kwargs)
        when /\.json$/
          read_json(io, symbolize_names:, compression: :none, **kwargs)
        when /\.json\.gz$/
          read_json(io, symbolize_names:, compression: :gzip, **kwargs)
        else
          raise ArgumentError, "unknown file extension for '#{filename}'"
        end
      end
    end

    def write(filename, data, **json_options)
      case filename.to_s
      when /\.jsonl$/
        write_jsonl(filename, data, compression: :none, **json_options)
      when /\.jsonl\.gz$/
        write_jsonl(filename, data, compression: :gzip, **json_options)
      when /\.json$/
        write_json(filename, data, compression: :none, **json_options)
      when /\.json\.gz$/
        write_json(filename, data, compression: :gzip, **json_options)
      else
        raise ArgumentError, "unknown file extension for '#{filename}'"
      end
    end

    def write_jsonl(filename, rows, compression: :gzip, **json_options)
      case compression
      when :gzip
        Zlib::GzipWriter.open(filename) do |gz|
          rows.each do |row|
            gz.puts(JSON.fast_generate(row, **json_options))
          end
        end
      else
        raise ArgumentError, "unsupported compression '#{compression}'"
      end
    end

    def write_json(filename, object, compression: :gzip, **json_options)
      case compression
      when :gzip
        Zlib::GzipWriter.open(filename) do |gz|
          gz.write(JSON.fast_generate(object, **json_options))
        end
      else
        raise ArgumentError, "unsupported compression '#{compression}"
      end
    end

    module_function :read, :write_jsonl, :write_json, :read_json, :read_jsonl, :decompress
  end
end