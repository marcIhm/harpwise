# -*- fill-column: 78 -*-

#
# General helper functions
#


def match_or cand, choices
  return unless cand
  matches = choices.select {|c| c.start_with?(cand)}
  yield "'#{cand}'", choices.join(', ') unless matches.length == 1
  matches[0]
end


def json_parse file
  begin
    JSON.parse(File.read(file))
  rescue JSON::ParserError => e
    fail "Cannot parse #{file}: #{e} !"
  rescue Errno::ENOENT => e
    fail "File #{file} does not exist !"
  end
end


def comment_in_chart? cell
  return true if cell.count('-') > 1 || cell.count('=') > 1
  return true if cell.match?(/^[- ]*$/)
  return false
end


def err_h text
  puts
  puts "ERROR: #{text} !"
  puts "(Hint: Invoke without arguments for usage information)"
  puts_err_context
  puts
  exit 1
end


def err_b text
  puts
  puts "ERROR: #{text} !"
  puts_err_context
  puts
  exit 1
end

def puts_err_context
  clauses = %w(type key scale).
              map {|var| eval("defined?($#{var})")  ?  ("#{var}=" + eval("$#{var}"))  :  nil}.
              select {|c| c}
  puts "(#{clauses.join(', ')})" if clauses.length > 0
  pp caller[1 .. -1]
end


def dbg text
  puts "DEBUG: #{text}" if $opts[:debug]
  text
end


