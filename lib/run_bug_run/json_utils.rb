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

    def load_jsonl(io, compression:, symbolize_names: true)
      decompress(io, compression) do |decompressed_io|
        decompressed_io.each_line.map do |line|
          JSON.parse(line, symbolize_names:)
        end
      end
    end

    def load_json(io, compression:, symbolize_names: true)
      decompress(io, compression) do |decompressed_io|
        JSON.parse(decompressed_io.read, symbolize_names:)
      end
    end

    def load_file(filename, symbolize_names: true)
      File.open(filename) do |io|
        case filename
        when /\.jsonl$/
          load_jsonl(io, symbolize_names:, compression: :none)
        when /\.jsonl\.gz$/
          load_jsonl(io, symbolize_names:, compression: :gzip)
        when /\.json$/
          load_json(io, symbolize_names:, compression: :none)
        when /\.json\.gz$/
          load_json(io, symbolize_names:, compression: :gzip)
        else
          raise ArgumentError, "unknown file extension for #{filename}"
        end
      end
    end

    def write_jsonl(filename, rows, compression: :gzip)
      case compression
      when :gzip
        Zlib::GzipWriter.open(filename) do |gz|
          rows.each do |row|
            gz.puts(JSON.fast_generate(row))
          end
        end
      else
        raise ArgumentError, "unsupported compression '#{compression}"
      end
    end

    def write_json(filename, object, compression: :gzip)
      case compression
      when :gzip
        Zlib::GzipWriter.open(filename) do |gz|
          gz.write(JSON.fast_generate(object))
        end
      else
        raise ArgumentError, "unsupported compression '#{compression}"
      end
    end

    module_function :load_file, :write_jsonl, :write_json, :load_json, :load_jsonl, :decompress
  end
end