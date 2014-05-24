require_relative '../test_helper'
require 'erb'

describe JunitMerge::App do
  TEMPLATE = File.read("#{ROOT}/test/template.xml.erb")

  use_temporary_directory "#{ROOT}/test/tmp"

  def create_file(path, tests)
    num_tests = tests.size
    num_failures = tests.values.count(:fail)
    num_errors = tests.values.count(:error)
    num_skipped = tests.values.count(:skipped)

    FileUtils.mkdir_p File.dirname(path)
    open(path, 'w') do |file|
      file.puts ERB.new(TEMPLATE).result(binding)
    end
  end

  def create_directory(path)
    FileUtils.mkdir_p path
  end

  def parse_file(path)
    Nokogiri::XML::Document.parse(File.read(path))
  end

  def results(node)
    results = []
    node.xpath('//testcase').each do |testcase_node|
      if !testcase_node.xpath('failure').empty?
        result = :fail
      elsif !testcase_node.xpath('error').empty?
        result = :error
      elsif !testcase_node.xpath('skipped').empty?
        result = :skipped
      else
        result = :pass
      end
      class_name = testcase_node['classname']
      test_name = testcase_node['name']
      results << ["#{class_name}.#{test_name}", result]
    end
    results
  end

  def summaries(node)
    summaries = []
    node.xpath('//testsuite | //testsuites').each do |node|
      summary = {}
      %w[tests failures errors skipped].each do |attribute|
        if (value = node[attribute])
          summary[attribute.to_sym] = Integer(value)
        end
      end
      summaries << summary
    end
    summaries
  end

  let(:stdin ) { StringIO.new }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:app) { JunitMerge::App.new(stdin: stdin, stdout: stdout, stderr: stderr) }

  describe "when merging files" do
    it "merges results" do
      create_file("#{tmp}/source.xml", 'a.a' => :pass, 'a.b' => :fail, 'a.c' => :error, 'a.d' => :skipped)
      create_file("#{tmp}/target.xml", 'a.a' => :fail, 'a.b' => :error, 'a.c' => :skipped, 'a.d' => :pass)
      app.run("#{tmp}/source.xml", "#{tmp}/target.xml").must_equal 0
      document = parse_file("#{tmp}/target.xml")
      results(document).must_equal([['a.a', :pass], ['a.b', :fail], ['a.c', :error], ['a.d', :skipped]])
      stdout.string.must_equal('')
      stderr.string.must_equal('')
    end

    it "updates summaries" do
      create_file("#{tmp}/source.xml", 'a.a' => :pass, 'a.b' => :skipped, 'a.c' => :fail)
      create_file("#{tmp}/target.xml", 'a.a' => :fail, 'a.b' => :error, 'a.c' => :fail)
      app.run("#{tmp}/source.xml", "#{tmp}/target.xml").must_equal 0
      document = parse_file("#{tmp}/target.xml")
      summaries(document).must_equal([{tests: 3, failures: 1, errors: 0, skipped: 1}])
      stdout.string.must_equal('')
      stderr.string.must_equal('')
    end

    it "does not modify nodes only in the target" do
      create_file("#{tmp}/source.xml", 'a.b' => :pass)
      create_file("#{tmp}/target.xml", 'a.a' => :pass, 'a.b' => :fail)
      app.run("#{tmp}/source.xml", "#{tmp}/target.xml").must_equal 0
      document = parse_file("#{tmp}/target.xml")
      results(document).must_equal([['a.a', :pass], ['a.b', :pass]])
      stdout.string.must_equal('')
      stderr.string.must_equal('')
    end

    it "appends nodes only in the source by default" do
      create_file("#{tmp}/source.xml", 'a.a' => :fail, 'a.b' => :error)
      create_file("#{tmp}/target.xml", 'a.a' => :pass)
      app.run("#{tmp}/source.xml", "#{tmp}/target.xml").must_equal 0
      document = parse_file("#{tmp}/target.xml")
      results(document).must_equal([['a.a', :fail], ['a.b', :error]])
      summaries(document).must_equal([{tests: 2, failures: 1, errors: 1, skipped: 0}])
      stdout.string.must_equal('')
      stderr.string.must_equal('')
    end

    it "skips nodes only in the source if --update-only is given" do
      create_file("#{tmp}/source.xml", 'a.a' => :fail, 'a.b' => :error)
      create_file("#{tmp}/target.xml", 'a.a' => :pass)
      app.run('--update-only', "#{tmp}/source.xml", "#{tmp}/target.xml").must_equal 0
      document = parse_file("#{tmp}/target.xml")
      results(document).must_equal([['a.a', :fail]])
      summaries(document).must_equal([{tests: 1, failures: 1, errors: 0, skipped: 0}])
      stdout.string.must_equal('')
      stderr.string.must_equal('')
    end

    it "correctly merges tests with metacharacters in the name" do
      create_file("#{tmp}/source.xml", 'a\'"a.b"\'b' => :pass)
      create_file("#{tmp}/target.xml", 'a\'"a.b"\'b' => :fail)
      app.run("#{tmp}/source.xml", "#{tmp}/target.xml").must_equal 0
      document = parse_file("#{tmp}/target.xml")
      results(document).must_equal([['a\'"a.b"\'b', :pass]])
      summaries(document).must_equal([{tests: 1, failures: 0, errors: 0, skipped: 0}])
      stdout.string.must_equal('')
      stderr.string.must_equal('')
    end

    it "correctly merges tests with the same name in different classes" do
      create_file("#{tmp}/source.xml", 'a.a' => :pass, 'b.a' => :fail)
      create_file("#{tmp}/target.xml", 'a.a' => :fail, 'b.a' => :pass)
      app.run("#{tmp}/source.xml", "#{tmp}/target.xml").must_equal 0
      document = parse_file("#{tmp}/target.xml")
      results(document).must_equal([['a.a', :pass], ['b.a', :fail]])
      stdout.string.must_equal('')
      stderr.string.must_equal('')
    end
  end

  describe "when merging directories" do
    it "updates target files from each file in the source directory" do
      create_file("#{tmp}/source/a.xml", 'a.a' => :pass, 'a.b' => :fail)
      create_file("#{tmp}/target/a.xml", 'a.a' => :fail, 'a.b' => :pass)
      app.run("#{tmp}/source", "#{tmp}/target").must_equal 0
      document = parse_file("#{tmp}/target/a.xml")
      results(document).must_equal([['a.a', :pass], ['a.b', :fail]])
      stdout.string.must_equal('')
      stderr.string.must_equal('')
    end

    it "does not modify files only in the target" do
      FileUtils.mkdir "#{tmp}/source"
      create_file("#{tmp}/target/a.xml", 'a.a' => :fail, 'a.b' => :pass)
      app.run("#{tmp}/source", "#{tmp}/target").must_equal 0
      document = parse_file("#{tmp}/target/a.xml")
      results(document).must_equal([['a.a', :fail], ['a.b', :pass]])
      stdout.string.must_equal('')
      stderr.string.must_equal('')
    end

    it "adds files only in the source by default" do
      create_file("#{tmp}/source/a.xml", 'a.a' => :fail, 'a.b' => :pass)
      create_directory("#{tmp}/target")
      app.run("#{tmp}/source", "#{tmp}/target").must_equal 0
      document = parse_file("#{tmp}/target/a.xml")
      results(document).must_equal([['a.a', :fail], ['a.b', :pass]])
      stdout.string.must_equal('')
      stderr.string.must_equal('')
    end

    it "skips files only in the source if --update-only is given" do
      create_file("#{tmp}/source/a.xml", 'a.a' => :fail, 'a.b' => :pass)
      create_directory("#{tmp}/target")
      app.run('--update-only', "#{tmp}/source", "#{tmp}/target").must_equal 0
      File.exist?("#{tmp}/target/a.xml").must_equal false
      stdout.string.must_equal('')
      stderr.string.must_equal('')
    end
  end

  it "does not complain about empty files" do
    FileUtils.touch "#{tmp}/source.xml"
    FileUtils.touch "#{tmp}/target.xml"
    app.run("#{tmp}/source.xml", "#{tmp}/target.xml").must_equal 0
    File.read("#{tmp}/target.xml").must_equal('')
    stdout.string.must_equal('')
    stderr.string.must_equal('')
  end

  it "works around invalid UTF-8" do
    create_file("#{tmp}/source.xml", "a.a\xFFb" => :pass)
    create_file("#{tmp}/target.xml", "a.a\xFFb" => :fail)
    app.run("#{tmp}/source.xml", "#{tmp}/target.xml").must_equal 0

    document = parse_file("#{tmp}/target.xml")
    results(document).must_equal([["a.a\uFFFDb", :pass]])

    stdout.string.must_equal('')
    stderr.string.must_equal('')
  end

  it "whines if the source does not exist" do
    FileUtils.touch "#{tmp}/target.xml"
    app.run("#{tmp}/source.xml", "#{tmp}/target.xml").must_equal 1
    File.read("#{tmp}/target.xml").must_equal('')
    stdout.string.must_equal('')
    stderr.string.must_match /no such file/
  end

  it "whines if the target does not exist" do
    FileUtils.touch "#{tmp}/source.xml"
    app.run("#{tmp}/source.xml", "#{tmp}/target.xml").must_equal 1
    stdout.string.must_equal('')
    stderr.string.must_match /no such file/
  end

  it "exits with a warning if no source files are given" do
    create_file("#{tmp}/target.xml", 'a.a' => :pass, 'a.b' => :fail)
    app.run("#{tmp}/target.xml").must_equal 0
    document = parse_file("#{tmp}/target.xml")
    results(document).must_equal([['a.a', :pass], ['a.b', :fail]])
    stdout.string.must_equal('')
    stderr.string.must_equal("warning: no source files given\n")
  end

  it "can merge multiple source files into the target in order" do
    create_file("#{tmp}/source1.xml", 'a.a' => :fail, 'a.b' => :fail)
    create_file("#{tmp}/source2.xml", 'a.a' => :pass)
    create_file("#{tmp}/target.xml", 'a.a' => :error, 'a.b' => :error, 'a.c' => :error)
    app.run("#{tmp}/source1.xml", "#{tmp}/source2.xml", "#{tmp}/target.xml").must_equal 0
    document = parse_file("#{tmp}/target.xml")
    results(document).must_equal([['a.a', :pass], ['a.b', :fail], ['a.c', :error]])
    stdout.string.must_equal('')
    stderr.string.must_equal('')
  end

  it "errors with a usage message if no args aren't given" do
    FileUtils.touch "#{tmp}/source.xml"
    app.run.must_equal 1
    File.read("#{tmp}/source.xml").must_equal('')
    stdout.string.must_equal('')
    stderr.string.must_match /USAGE/
  end
end
