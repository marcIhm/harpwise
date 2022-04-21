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


def err text
  sane_term
  puts
  puts "ERROR: #{text} !"
  puts_err_context
  puts
  exit 1
end


def puts_err_context
  clauses = [:mode, :type, :key, :scale].map do |var|
      val = if $err_binding && eval("defined?(#{var})",$err_binding)
              eval("#{var}", $err_binding)
            elsif eval("defined?($#{var})")
              eval("$#{var}")
            else
              nil
            end
      val  ?  "#{var}=#{val}"  :  "#{var} is not set"  
  end.select(&:itself)
  puts
  puts "(result of argument processing so far: #{clauses.join(', ')})" if clauses.length > 0
end


def file2scale file, type = $type
  %w(holes notes).each do |what|
    parts = ($scale_files_template % [type, '|', what]).split('|')
    return file[parts[0].length .. - parts[1].length - 1] if file[parts[1]]
  end
end


def scales_for_type type
  Dir[$scale_files_template % [type, '*', '{holes,notes}']].map {|file| file2scale(file,type)}.sort
end
