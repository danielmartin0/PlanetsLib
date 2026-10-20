#!/usr/bin/env ruby
# frozen_string_literal: true

# Summarize FUnit JSON reports for GitHub Actions.
#
# FUnit writes one JSON report per scenario (see
# test-mods/planetslib-funit-data/tests/scenario/control.lua). On a red run the
# raw reports are buried in the `unit-test-job` artifact. This script turns
# them into a GitHub step summary that lists every scenario and every failing
# test, so a failure can be diagnosed without downloading the artifact.
#
# Usage:
#   ruby summarize_funit_results.rb REPORT_DIR [options]
#
#   --expect NAMES   Comma-separated report names that must be present. Names
#                    that produced no report are called out explicitly.
#   --log FILE       Captured entrypoint output. The per-scenario section is
#                    shown when a scenario produced no usable report.
#   --output FILE    Append the Markdown to FILE (default:
#                    $GITHUB_STEP_SUMMARY, or stdout when unset).
#   --[no-]annotate  Emit GitHub error annotations for failures (default: on
#                    when GITHUB_ACTIONS is set).
#
# The script exits 0 when tests fail or reports are missing; it is a reporting
# step and the JUnit conversion step is what fails the job. It exits nonzero
# only for an invalid invocation.

require 'json'
require 'optparse'

MAX_TEST_DETAIL_CHARS = 4_000
MAX_LOG_LINES = 80
MAX_ANNOTATION_CHARS = 1_500

Report = Struct.new(:name, :path, :data, :load_error, keyword_init: true) do
  def testcases
    return [] unless data && data['testcases'].is_a?(Array)

    data['testcases']
  end

  def failures
    testcases.select { |testcase| testcase['failure'] && !testcase['error'] }
  end

  def errors
    testcases.select { |testcase| testcase['error'] }
  end

  def failed_testcases
    testcases.select { |testcase| testcase['error'] || testcase['failure'] }
  end

  def tests
    testcases.size
  end

  def missing?
    data.nil? && load_error.nil?
  end

  def invalid?
    data.nil? && !load_error.nil?
  end

  def failed?
    !failures.empty? || !errors.empty?
  end

  def result
    return 'missing' if missing?
    return 'invalid' if invalid?
    return 'failed' if failed?

    'passed'
  end
end

def load_report(name, path)
  unless File.file?(path) && File.size?(path)
    return Report.new(name: name, path: path, data: nil, load_error: nil)
  end

  begin
    data = JSON.parse(File.read(path))
  rescue JSON::ParserError => e
    return Report.new(name: name, path: path, data: nil,
                      load_error: "JSON parse error: #{e.message}")
  rescue StandardError => e
    return Report.new(name: name, path: path, data: nil,
                      load_error: "could not read report: #{e.message}")
  end

  valid = data.is_a?(Hash) &&
          data['testcases'].is_a?(Array) &&
          data['testcases'].all? do |testcase|
            testcase.is_a?(Hash) && testcase['name'].is_a?(String)
          end

  unless valid
    return Report.new(name: name, path: path, data: nil,
                      load_error: 'expected an object with a named testcases array')
  end

  Report.new(name: name, path: path, data: data, load_error: nil)
end

# Escape text for inline HTML/Markdown.
def html_escape(text)
  text.to_s
      .gsub('&', '&amp;')
      .gsub('<', '&lt;')
      .gsub('>', '&gt;')
end

# Escape text for a Markdown table cell.
def table_escape(text)
  text.to_s.gsub('|', '\\|').gsub("\r", ' ').gsub("\n", ' ')
end

def truncate(text, limit)
  text = text.to_s
  return text if text.length <= limit

  "#{text[0, limit]}\n… (truncated)"
end

# Find the log lines belonging to one scenario. The entrypoint prints
# "____SCENARIO____: <name>" before each run, so section boundaries are
# unambiguous even though all scenarios write to one log.
def scenario_log(log_path, name)
  return nil unless log_path && File.file?(log_path)

  text = File.read(log_path, mode: 'rb')
  text = text.encode('UTF-8', invalid: :replace, undef: :replace)
  lines = text.lines
  marker = "____SCENARIO____: #{name}"
  start = lines.index { |line| line.strip == marker }
  # The entrypoint prints the marker before starting a scenario, so no marker
  # means that scenario never ran. Showing another scenario's log would be
  # misleading; report only that the report is missing.
  return nil unless start

  section = []
  lines[(start + 1)..].each do |line|
    break if line.start_with?('____SCENARIO____:')

    section << line
  end

  lines = section.last(MAX_LOG_LINES)
  return nil if lines.empty?

  lines.join.chomp
rescue StandardError
  nil
end

def annotation_escape(text)
  text.to_s
      .gsub('%', '%25')
      .gsub("\r", '%0D')
      .gsub("\n", '%0A')
end

def annotation_title(text)
  text.to_s
      .gsub('%', '%25')
      .gsub('::', ': ')
      .gsub(/[\r\n]+/, ' ')
      .strip
end

def emit_annotation(level, title, message)
  message = truncate(message, MAX_ANNOTATION_CHARS)
  puts "::#{level} title=#{annotation_title(title)}::#{annotation_escape(message)}"
end

def failure_message(testcase)
  detail = testcase['error'] || testcase['failure']
  return '' unless detail.is_a?(Hash)

  [detail['type'], detail['message']].compact.reject(&:empty?).join(': ')
end

def failure_content(testcase)
  detail = testcase['error'] || testcase['failure']
  return nil unless detail.is_a?(Hash)

  detail['content']
end

def invalid_report_reason(report)
  if report.missing?
    "No report was produced. Expected `#{report.path}`."
  else
    "The report could not be used: #{report.load_error}."
  end
end

def append_log_details(lines, log_path, report)
  log = scenario_log(log_path, report.name)
  return unless log

  lines << '<details><summary>Last lines of the scenario log</summary>'
  lines << ''
  lines << '<pre>'
  lines << html_escape(log)
  lines << '</pre>'
  lines << ''
  lines << '</details>'
  lines << ''
end

# ---------------------------------------------------------------------------
# Command line
# ---------------------------------------------------------------------------

options = {
  expected: [],
  log: nil,
  output: ENV['GITHUB_STEP_SUMMARY'],
  annotate: ENV['GITHUB_ACTIONS'] == 'true'
}

parser = OptionParser.new do |opts|
  opts.banner = 'Usage: summarize_funit_results.rb REPORT_DIR [options]'
  opts.separator ''
  opts.separator 'Turn FUnit JSON reports into a GitHub Actions step summary.'
  opts.separator ''
  opts.on('--expect NAMES',
          'Comma-separated report names that must be present') do |value|
    options[:expected] = value.split(',').map(&:strip).reject(&:empty?)
  end
  opts.on('--log FILE', 'Captured headless Factorio output') do |value|
    options[:log] = value
  end
  opts.on('--output FILE',
          'Append Markdown to FILE (default: $GITHUB_STEP_SUMMARY)') do |value|
    options[:output] = value
  end
  opts.on('--[no-]annotate',
          'Emit GitHub error annotations for failures') do |value|
    options[:annotate] = value
  end
  opts.on('-h', '--help', 'Print this help') do
    puts opts
    exit 0
  end
end

begin
  parser.parse!
rescue OptionParser::ParseError => e
  warn "Error: #{e.message}"
  warn parser
  exit 2
end

reports_dir = ARGV.shift
if reports_dir.nil? || !ARGV.empty?
  warn parser
  exit 2
end

# ---------------------------------------------------------------------------
# Discover and load reports
# ---------------------------------------------------------------------------

prefix = 'funit-report-'
suffix = '.json'
discovered = []
if Dir.exist?(reports_dir)
  Dir.glob(File.join(reports_dir, "#{prefix}*#{suffix}")).sort.each do |path|
    basename = File.basename(path)
    next unless basename.start_with?(prefix) && basename.end_with?(suffix)

    discovered << basename[prefix.length...-suffix.length]
  end
end

names = (options[:expected] + discovered).uniq
reports = names.map do |name|
  path = File.join(reports_dir, "#{prefix}#{name}#{suffix}")
  load_report(name, path)
end

# ---------------------------------------------------------------------------
# Build the summary
# ---------------------------------------------------------------------------

total_tests = reports.sum(&:tests)
total_failures = reports.sum { |report| report.failures.size }
total_errors = reports.sum { |report| report.errors.size }
incomplete = reports.select { |report| report.missing? || report.invalid? }
failed = reports.select(&:failed?)
bad = incomplete + failed
all_passed = bad.empty? && !reports.empty?

lines = ['## FUnit results', '']

if reports.empty?
  lines << '⚠️ **No FUnit reports were found.**'
elsif all_passed
  headline =
    if reports.size == 1
      'The FUnit scenario passed'
    else
      "All #{reports.size} FUnit scenarios passed"
    end
  lines << "✅ **#{headline}** " \
           "(#{total_tests} tests, 0 failures, 0 errors)."
else
  summary = []
  summary << "#{failed.size} of #{reports.size} scenarios failed" unless failed.empty?
  summary << "#{incomplete.size} of #{reports.size} scenarios did not report" unless incomplete.empty?
  counts = []
  counts << "#{total_failures} test #{total_failures == 1 ? 'failure' : 'failures'}"
  counts << "#{total_errors} #{total_errors == 1 ? 'error' : 'errors'}"
  counts << "#{total_tests} tests completed"
  headline = failed.empty? ? 'FUnit did not complete' : 'FUnit failed'
  lines << "❌ **#{headline}** — #{summary.join(', ')} " \
           "(#{counts.join(', ')})."
end

unless reports.empty?
  lines << ''
  lines << '| Scenario | Result | Tests | Failures | Errors |'
  lines << '| --- | --- | ---: | ---: | ---: |'

  reports.each do |report|
    result =
      case report.result
      when 'passed' then '✅ Passed'
      when 'failed' then '❌ Failed'
      when 'missing' then '⚠️ No report'
      when 'invalid' then '❌ Invalid report'
      end

    counts =
      if report.missing? || report.invalid?
        ['—', '—', '—']
      else
        [report.tests, report.failures.size, report.errors.size]
      end

    lines << "| #{table_escape(report.name)} | #{result} | #{counts.join(' | ')} |"
  end

  lines << ''
end

failed.each do |report|
  count_parts = []
  count_parts << "#{report.failures.size} #{report.failures.size == 1 ? 'failure' : 'failures'}"
  count_parts << "#{report.errors.size} #{report.errors.size == 1 ? 'error' : 'errors'}"
  lines << "### ❌ #{table_escape(report.name)} — #{count_parts.join(', ')}"
  lines << ''

  report.failed_testcases.each do |testcase|
    lines << "#### `#{testcase['name'].gsub('`', "'")}`"
    lines << ''

    message = failure_message(testcase).gsub(/\s+/, ' ').strip
    lines << "**#{html_escape(message)}**" unless message.empty?
    lines << ''

    content = failure_content(testcase)
    if content && !content.empty?
      lines << '<details><summary>Test log</summary>'
      lines << ''
      lines << '<pre>'
      lines << html_escape(truncate(content, MAX_TEST_DETAIL_CHARS))
      lines << '</pre>'
      lines << ''
      lines << '</details>'
      lines << ''
    end
  end
end

incomplete.each do |report|
  lines << "### ⚠️ #{table_escape(report.name)} — no usable report"
  lines << ''
  lines << invalid_report_reason(report)
  lines << ''
  append_log_details(lines, options[:log], report)
end

lines << '_FUnit JSON reports and the full headless log are attached to the ' \
         '`unit-test-job` artifact for this run._'
lines << ''

markdown = lines.join("\n")

if options[:output] && !options[:output].empty?
  File.open(options[:output], 'a') { |file| file.write(markdown) }
  puts "FUnit summary written to #{options[:output]}"
else
  puts markdown
end

# Annotations show up next to the workflow run and in the pull request checks
# view, where they are easier to spot than the step summary.
if options[:annotate]
  failed.each do |report|
    report.failed_testcases.each do |testcase|
      emit_annotation(
        'error',
        "FUnit #{report.name}: #{testcase['name']}",
        failure_message(testcase)
      )
    end
  end

  incomplete.each do |report|
    emit_annotation('error', "FUnit #{report.name}",
                    invalid_report_reason(report))
  end
end

exit 0
