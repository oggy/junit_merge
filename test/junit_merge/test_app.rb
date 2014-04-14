require_relative '../test_helper'
require 'erb'

describe JunitMerge::App do
  TEMPLATE = File.read("#{ROOT}/test/template.xml.erb")

  use_temporary_directory "#{ROOT}/test/tmp"

  def create_file(path, tests)
    num_tests = tests.size
    num_failures = tests.values.count(:fail)
    num_errors = tests.values.count(:error)

    FileUtils.mkdir_p File.dirname(path)
    open(path, 'w') do |file|
      file.puts ERB.new(TEMPLATE).result(binding)
    end
  end

  def create_directory(path)
    FileUtils.mkdir_p path
  end

  def parse_file(path)
    document = Nokogiri::XML::Document.parse(File.read(path))
    results = []
    document.xpath('//testcase').each do |testcase_node|
      if !testcase_node.xpath('failure').empty?
        result = :fail
      else
        result = :pass
      end
      class_name = testcase_node['classname']
      test_name = testcase_node['name']
      results << ["#{class_name}.#{test_name}", result]
    end
    results
  end

  let(:stdin ) { StringIO.new }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:app) { JunitMerge::App.new(stdin: stdin, stdout: stdout, stderr: stderr) }

  describe "when merging files" do
    it "merges files together" do
      create_file("#{tmp}/source.xml", 'a.a' => :pass, 'a.b' => :fail)
      create_file("#{tmp}/target.xml", 'a.a' => :fail, 'a.b' => :pass)
      app.run("#{tmp}/source.xml", "#{tmp}/target.xml").must_equal 0
      results = parse_file("#{tmp}/target.xml")
      results.must_equal([['a.a', :pass], ['a.b', :fail]])
      stdout.string.must_equal('')
      stderr.string.must_equal('')
    end

    it "does not modify nodes only in the target" do
      create_file("#{tmp}/source.xml", 'a.b' => :pass)
      create_file("#{tmp}/target.xml", 'a.a' => :pass, 'a.b' => :fail)
      app.run("#{tmp}/source.xml", "#{tmp}/target.xml").must_equal 0
      results = parse_file("#{tmp}/target.xml")
      results.must_equal([['a.a', :pass], ['a.b', :pass]])
      stdout.string.must_equal('')
      stderr.string.must_equal('')
    end

    it "appends nodes only in the source" do
      create_file("#{tmp}/source.xml", 'a.a' => :pass, 'a.b' => :pass)
      create_file("#{tmp}/target.xml", 'a.a' => :fail)
      app.run("#{tmp}/source.xml", "#{tmp}/target.xml").must_equal 0
      result = parse_file("#{tmp}/target.xml")
      result.must_equal([['a.a', :pass], ['a.b', :pass]])
      stdout.string.must_equal('')
      stderr.string.must_equal('')
    end
  end

  describe "when merging directories" do
    it "updates target files from each file in the source directory" do
      create_file("#{tmp}/source/a.xml", 'a.a' => :pass, 'a.b' => :fail)
      create_file("#{tmp}/target/a.xml", 'a.a' => :fail, 'a.b' => :pass)
      app.run("#{tmp}/source", "#{tmp}/target").must_equal 0
      result = parse_file("#{tmp}/target/a.xml")
      result.must_equal([['a.a', :pass], ['a.b', :fail]])
      stdout.string.must_equal('')
      stderr.string.must_equal('')
    end

    it "does not modify files only in the target" do
      FileUtils.mkdir "#{tmp}/source"
      create_file("#{tmp}/target/a.xml", 'a.a' => :fail, 'a.b' => :pass)
      app.run("#{tmp}/source", "#{tmp}/target").must_equal 0
      result = parse_file("#{tmp}/target/a.xml")
      result.must_equal([['a.a', :fail], ['a.b', :pass]])
      stdout.string.must_equal('')
      stderr.string.must_equal('')
    end

    it "adds files only in the source" do
      create_file("#{tmp}/source/a.xml", 'a.a' => :fail, 'a.b' => :pass)
      create_directory("#{tmp}/target")
      app.run("#{tmp}/source", "#{tmp}/target").must_equal 0
      result = parse_file("#{tmp}/target/a.xml")
      result.must_equal([['a.a', :fail], ['a.b', :pass]])
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

  it "errors with a usage message if 2 args aren't given" do
    FileUtils.touch "#{tmp}/source.xml"
    app.run("#{tmp}/source.xml").must_equal 1
    File.read("#{tmp}/source.xml").must_equal('')
    stdout.string.must_equal('')
    stderr.string.must_match /USAGE/
  end
end
