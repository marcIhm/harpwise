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


def yaml_parse file
  begin
    YAML.load_file(file)
  rescue Psych::SyntaxError => e
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
              map {|var| eval("defined?($#{var})")  ?  ("#{var}=" + eval("$#{var}").to_s)  :  nil}.
              select {|c| c}
  puts "(#{clauses.join(', ')})" if clauses.length > 0
  puts caller[1 .. -1].map {|l| l + "\n"}.reverse
end


def dbg text
  puts "DEBUG: #{text}" if $opts[:debug]
  text
end


def file2scale file, type = $type
  %w(holes notes).each do |what|
    parts = ($scale_files_template % [type, '|', what]).split('|')
    return file[parts[0].length .. - parts[1].length - 1] if file[parts[1]]
  end
end
