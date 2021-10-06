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
