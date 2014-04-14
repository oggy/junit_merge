require 'find'
require 'fileutils'
require 'nokogiri'

module JunitMerge
  class App
    Error = Class.new(RuntimeError)

    def initialize(options={})
      @stdin  = options[:stdin ] || STDIN
      @stdout = options[:stdout] || STDOUT
      @stderr = options[:stderr] || STDERR
    end

    attr_reader :stdin, :stdout, :stderr

    def run(*args)
      source_path, target_path = parse_args(args)

      not_found = [source_path, target_path].select { |path| !File.exist?(path) }
      not_found.empty? or
        raise Error, "no such file: #{not_found.join(', ')}"

      if File.directory?(source_path)
        Find.find(source_path) do |source_file_path|
          next if !File.file?(source_file_path)
          target_file_path = source_file_path.sub(source_path, target_path)
          if File.exist?(target_file_path)
            merge_file(source_file_path, target_file_path)
          else
            FileUtils.mkdir_p(File.dirname(target_file_path))
            FileUtils.cp(source_file_path, target_file_path)
          end
        end
      elsif File.exist?(source_path)
        merge_file(source_path, target_path)
      else
        raise Error, "no such file: #{source_path}"
      end
      0
    rescue Error => error
      stderr.puts error.message
      1
    end

    private

    def merge_file(source_path, target_path)
      source_text = File.read(source_path)
      target_text = File.read(target_path)

      if target_text =~ /\A\s*\z/m
        return
      end

      if source_text =~ /\A\s*\z/m
        FileUtils.cp source_path, target_path
        return
      end

      source = Nokogiri::XML::Document.parse(source_text)
      target = Nokogiri::XML::Document.parse(target_text)

      source.xpath("//testsuite/testcase").each do |node|
        original = target.xpath("testsuite/testcase[@name='#{node.attribute('name')}']").first
        if original
          original.replace(node)
        else
          testsuite = target.xpath("testsuite").first
          testsuite.add_child(node)
        end
      end

      open(target_path, 'w') { |f| f.write(target.to_s) }
    end

    def parse_args(args)
      args.size == 2 or
        raise Error, usage
      args
    end

    def usage
      "USAGE: #$0 SOURCE TARGET"
    end
  end
end
