require 'optparse'
require 'json'
require 'rexml/document'

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: ruby parse_funit_json.rb DIRECTORY [options]"

  opts.on("-o", "--output FILE", "Write output to FILE (default: stdout)") do |file|
    options[:output] = file
  end

  opts.on("-h", "--help", "Print this help") do
    puts opts
    exit
  end
end.parse!

if ARGV.empty?
  abort "Error: Directory is required.\nUsage: ruby parse_funit_json.rb DIRECTORY [options]"
end

input_dir = ARGV[0]
unless Dir.exist?(input_dir)
  abort "Error: Directory '#{input_dir}' does not exist."
end

json_files = Dir.glob(File.join(input_dir, "*.json"))
if json_files.empty?
  abort "Error: No json files found in '#{input_dir}'."
end

fail_job = false
doc = REXML::Document.new
doc << REXML::XMLDecl.new('1.0', 'UTF-8')
testsuites = REXML::Element.new('testsuites')
doc << testsuites
json_files.each do |file|
  begin
    suite_data = JSON.parse(File.read(file))
    unless suite_data.is_a?(Hash) && suite_data['testcases'].is_a?(Array) &&
           suite_data['testcases'].all? { |tc| tc.is_a?(Hash) && tc['name'].is_a?(String) }
      raise ArgumentError, 'Expected a suite containing an array of named testcases'
    end

    {
      'tests' => suite_data['testcases'].size,
      'failures' => suite_data['testcases'].count { |tc| tc['failure'] && !tc['error'] },
      'errors' => suite_data['testcases'].count { |tc| tc['error'] }
    }.each do |field, expected|
      unless suite_data[field].is_a?(Integer) && suite_data[field] == expected
        raise ArgumentError, "#{field} must match testcase count (expected #{expected})"
      end
    end

    testsuite = REXML::Element.new('testsuite')
    testsuite.add_attribute('name',      suite_data['name'] || File.basename(file, '.json'))
    testsuite.add_attribute('tests',     suite_data['tests'] || 0)
    testsuite.add_attribute('failures',  suite_data['failures'] || 0)
    testsuite.add_attribute('errors',    suite_data['errors'] || 0)
    testsuite.add_attribute('skipped',   suite_data['skipped'] || 0)
    testsuite.add_attribute('time',      suite_data['time'] || 0)

    suite_data['testcases']&.each do |tc|
      testcase = REXML::Element.new('testcase')
      testcase.add_attribute('name',      tc['name'])
      testcase.add_attribute('classname', tc['classname'])
      testcase.add_attribute('time',      tc['time'] || 0)
      if tc['error']
        fail_job = true
        error = REXML::Element.new('error')
        error.add_attribute('message', tc['error']['message'])
        error.add_attribute('type',    tc['error']['type'])
        error.add_text(tc['error']['content'] || '') if tc['error']['content']
        testcase << error
      elsif tc['failure']
        fail_job = true
        failure = REXML::Element.new('failure')
        failure.add_attribute('message', tc['failure']['message'])
        failure.add_attribute('type',    tc['failure']['type'])
        failure.add_text(tc['failure']['content'] || '') if tc['failure']['content']
        testcase << failure
      end
      testsuite << testcase
    end
    testsuites << testsuite
  rescue JSON::ParserError, ArgumentError => e
    fail_job = true
    warn "Error: Invalid report #{file} — #{e.message}"
  end
end

formatter = REXML::Formatters::Pretty.new(2)
formatter.compact = true
if options[:output]
  File.open(options[:output], "w") do |f|
    formatter.write(doc, f)
    f.puts
  end
  puts "JUnit XML written to #{options[:output]}"
else
  formatter.write(doc, $stdout)
  puts
end

exit 1 if fail_job
exit 0