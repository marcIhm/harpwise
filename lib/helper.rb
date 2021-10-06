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
