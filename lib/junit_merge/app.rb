require 'optparse'
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
      @update_only = false
    end

    attr_reader :stdin, :stdout, :stderr

    def run(*args)
      *source_paths, target_path = parse_args(args)
      all_paths = [*source_paths, target_path]

      not_found = all_paths.select { |path| !File.exist?(path) }
      not_found.empty? or
        raise Error, "no such file(s): #{not_found.join(', ')}"

      if source_paths.empty?
        stderr.puts "warning: no source files given"
      else
        source_paths.each do |source_path|
          if File.directory?(source_path)
            Find.find(source_path) do |source_file_path|
              next if !File.file?(source_file_path)
              target_file_path = source_file_path.sub(source_path, target_path)
              if File.exist?(target_file_path)
                merge_file(source_file_path, target_file_path)
              elsif !@update_only
                FileUtils.mkdir_p(File.dirname(target_file_path))
                FileUtils.cp(source_file_path, target_file_path)
              end
            end
          else File.exist?(source_path)
            merge_file(source_path, target_path)
          end
        end
      end
      0
    rescue Error, OptionParser::ParseError => error
      stderr.puts error.message
      1
    end

    private

    def merge_file(source_path, target_path)
      source_text = File.read(source_path).encode!('UTF-8', invalid: :replace)
      target_text = File.read(target_path).encode!('UTF-8', invalid: :replace)

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
        summary_diff = SummaryDiff.new

        predicates = [
          attribute_predicate('classname', node['classname']),
          attribute_predicate('name', node['name']),
        ].join(' and ')
        original = target.xpath("testsuite/testcase[#{predicates}]").first

        if original
          summary_diff.add(node, 1)
          summary_diff.add(original, -1)
          original.replace(node)
        elsif !@update_only
          summary_diff.add(node, 1)
          testsuite = target.xpath("testsuite").first
          testsuite.add_child(node)
        end

        node.ancestors.select { |a| a.name =~ /\Atestsuite?\z/ }.each do |suite|
          summary_diff.apply_to(suite)
        end
      end

      open(target_path, 'w') { |f| f.write(target.to_s) }
    end

    def attribute_predicate(name, value)
      # XPath doesn't let you escape the delimiting quotes. Need concat() here
      # to support the general case.
      escaped = value.to_s.gsub('"', '", \'"\', "')
      "@#{name}=concat('', \"#{escaped}\")"
    end

    def apply_summary_diff(diff, node)
      summary_diff.each do |key, delta|
      end
    end

    SummaryDiff = Struct.new(:tests, :failures, :errors, :skipped) do
      def initialize
        self.tests = self.failures = self.errors = self.skipped = 0
      end

      def add(test_node, delta)
        self.tests += delta
        self.failures += delta if !test_node.xpath('failure').empty?
        self.errors += delta if !test_node.xpath('error').empty?
        self.skipped += delta if !test_node.xpath('skipped').empty?
      end

      def apply_to(node)
        %w[tests failures errors skipped].each do |attribute|
          if (value = node[attribute])
            node[attribute] = value.to_i + send(attribute)
          end
        end
      end
    end

    def parse_args(args)
      parser = OptionParser.new do |parser|
        parser.banner = "USAGE: #$0 [options] SOURCES ... TARGET"
        parser.on '-u', '--update-only', "Only update nodes, don't append new nodes in the source." do
          @update_only = true
        end
      end

      parser.parse!(args)

      args.size >= 1 or
        raise Error, parser.banner

      args
    end
  end
end
