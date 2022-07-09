#
# Handling of licks
#


$lick_file_mod_time = nil
$lick_file = nil

def read_licks graceful = false

  $lick_file = lfile = get_lick_file
  $lick_file_mod_time = File.mtime($lick_file)
  word_re ='[[:alnum:]][-_:/\.[:alnum:]]*'
  all_keys = %w(holes notes rec rec.start rec.length rec.key tags tags.add desc desc.add)

  all_licks = []
  licks = nil
  derived = []
  all_lick_names = Set.new
  default = Hash.new
  vars = Hash.new
  lick = name = nil

  (File.readlines(lfile) << '[default]').each do |line|  # trigger checks for new lick even at end of file
    line.chomp!
    line.gsub!(/#.*/,'')
    line.strip!
    next if line == ''
    derived << line

    # [start new lick or default]
    if md = line.match(/^\[(#{word_re})\]$/)
      derived.insert(-2,'') # empty line before in derived
      nname = md[1]

      # Do final processing of previous lick: merging with default and replacement of vars
      if lick
        if name == 'default'
          default = lick
        elsif name == 'vars'
          # vars have already been assigned; nothing to do here
        else
          err "Lick [#{name}] does not contain any holes" unless lick[:holes]  
          lick[:tags] = replace_vars(vars,([lick[:tags] || default[:tags]] + [lick[:tags_add]]).flatten.select(&:itself),name)
          lick[:desc] = lick[:desc] || default[:desc] || ''
          lick[:desc] += '; ' + lick[:desc_add] if lick[:desc_add] && lick[:desc_add].length > 0
          lick[:rec_key] ||= 'c'
          lick[:rec_key] = replace_vars(vars,[lick[:rec_key]],name)[0]
          all_licks << lick
        end
      end
      name = nname

      # start with new lick
      unless %w(default vars).include?(nname)
        err "Lick '#{nname}' has already appeared before (#{lfile})" if all_lick_names.include?(name)
        all_lick_names << nname
      end
      lick = Hash.new
      lick[:name] = nname

    # [empty section]
    elsif line.match?(/^ *\[\] *$/)
      err "Lick name [] cannot be empty (#{lfile})"

    # [invalid section]
    elsif md = line.match(/^ *\[(.*)\] *$/)
      err "Invalid lick name: '#{md[1]}', only letters, numbers, underscore and minus are allowed (#{lfile})"

    # $var = value
    elsif md = line.match(/^ *(\$#{word_re}) *= *(#{word_re})$/)
      var, value = md[1..2]
      err "Variables (here: #{var}) may only be assigned in section [vars]; not in [#{name}] (#{lfile})" unless name == 'vars'
      vars[var] = value

    # tags.add = value1 value2 ...
    # tags = value1 value2 ...
    elsif (md = line.match(/^ *(tags.add) *= *(.*?) *$/))||
          (md = line.match(/^ *(tags) *= *(.*?) *$/))
      var, tags = md[1 .. 2]
      var = var.gsub('.','_').to_sym
      err "Section [default] does only allow 'tags', but not 'tags.add'" if name == 'default' && var == :tags_add
      tags.split.each do |tag|
        err "Tags must consist of word characters; '#{tag}' does not" unless tag.match?(/^#{word_re}$/) || tag.match?(/^\$#{word_re}$/) 
      end
      lick[var] = tags.split

    # holes = value1 value2 ...
    elsif md = line.match(/^ *holes *= *(.*?) *$/)
      holes = md[1]
      err "File #{lfile} should only contain key 'notes', not 'holes' (below [#{name}])" if lfile['notes']
      lick[:holes] = holes.split.map do |hole|
        err("Hole '#{hole}' from #{lfile} is not among holes of harp #{$harp_holes}") unless musical_event?(hole) || $harp_holes.include?(hole)
        hole
      end
      err "Lick #{name} does not contain any holes (#{lfile})" unless lick[:holes].length > 0
      derived[-1] = "notes = " + holes.split.map do |hoe|
        musical_event?(hoe)  ?  hoe  :  $harp[hoe][:note]
      end.join(' ')

    # notes = value1 value2 ...
    elsif md = line.match(/^ *notes *= *(.*?) *$/)
      notes = md[1]
      err "File #{lfile} should only contain key 'holes', not 'notes' (below [#{name}])" if lfile['holes']
      lick[:holes] = notes.split.map do |note|
        err("Note '#{note}' from #{lfile} is not among notes of harp #{$harp_notes}") unless musical_event?(note) || $harp_notes.include?(note)
        $note2hole[note]
      end
      derived[-1] = "  holes = " + lick['holes'].join(' ')

    # desc.add = multi word description
    # desc = multi word description
    elsif (md = line.match(/^ *(desc.add) *= *(.*?) *$/)) ||
          (md = line.match(/^ *(desc) *= *(.*?) *$/))
      var, desc = md[1 .. 2]
      var = var.gsub('.','_').to_sym
      err "Section [default] does only allow 'desc', but not 'desc.add'" if name == 'default' && var == :desc_add
      lick[var] = desc
      
    # key = value  (for remaining keys, e.g. rec)
    elsif md = line.match(/^ *(#{word_re}) *= *(#{word_re})$/)
      key, value = md[1..2]

      if name == 'default'
        # correct assignment has been handled before
        err "Default section only allows key 'tags', not '#{key}'" 
      elsif name == 'vars'
        # correct assignments have been handled before
        err "Section [vars] may only contain variables (starting with '$'), not #{key} (#{lfile})"
      # normal lick
      else
        # tags, holes and notes have been handled above special
        if all_keys.include?(key)
          lick[key.gsub('.','_').to_sym] = value
        else
          err "Unknown key '#{key}', none of #{all_keys}"
        end
        if key == 'rec'
          file = $lick_dir + '/recordings/' + value
          err "File #{file} does not exist" unless File.exist?(file)
        elsif key == 'rec.key'
          err "Unknown key '#{value}'; none of #{$conf[:all_keys]}" unless $conf[:all_keys].include?(value)
        end
      end
    else
      err "Cannot parse this line: '#{line}' (#{lfile})"
    end
  end # end of processing lines in file

  err("No licks found in #{lfile}") unless all_licks.length > 0 

  # write derived lick file
  dfile = File.dirname(lfile) + '/derived_' + File.basename(lfile).sub(/holes|notes/, lfile['holes'] ? 'notes' : 'holes')
  File.open(dfile,'w') do |df|
    df.write <<~end_of_content
    
         #
         # derived lick file with #{dfile['holes'] ? 'holes' : 'notes'}
         # created from #{lfile}
         #
           
         end_of_content
    df.puts derived.join("\n") + "\n"
  end

  # keep only those licks, that match argument --tags
  keep = Set.new($opts[:tags]&.split(','))
  discard = Set.new($opts[:no_tags]&.split(','))
  tags_in_opts = Set.new(discard + keep)
  tags_in_licks = Set.new(all_licks.map {|l| l[:tags]}.flatten)

  if $opts[:tags] == 'print'
    print_lick_and_tag_info all_licks, licks
    exit
  end

  if $opts[:tags] == 'dump'
    pp all_licks
    exit
  end

  if $opts[:tags] == 'hist' || $opts[:tags] == 'history'
    print_last_licks_from_journal all_licks
    exit
  end

  if keep.intersection(discard).any?
    if graceful
      return [[],[]]
    else
      err "No licks can be found, because options '--tags' and '--no-tags' have this intersection: #{keep.intersection(discard).to_a}"
    end
  end
    
  if !tags_in_opts.subset?(tags_in_licks)
    if graceful
      return [[],[]]
    else
      err "There are some tags in option '--tags' and '--no-tags' #{tags_in_opts.to_a} which are not in lick file #{lfile} #{tags_in_licks.to_a}; unknown in '--tags' and '--no-tags' are: #{(tags_in_opts - tags_in_licks).to_a}"
    end
  end
  
  licks = all_licks.
            select {|lick| keep.empty? || (keep.to_a & lick[:tags]).any?}.
            reject {|lick| discard.any? && (discard.to_a & lick[:tags]).any?}.
            select {|lick| lick[:holes].length <= ( $opts[:max_holes] || 1000 )}.
            select {|lick| lick[:holes].length >= ( $opts[:min_holes] || 0 )}.
            uniq {|lick| lick[:holes]}

  err("None of the #{all_licks.length} licks from #{lfile} has been selected when applying options '--tags' and '--no-tags', '--max-holes' and '--min-holes'") if licks.length == 0

  [all_licks, licks]
end


def create_initial_lick_file lfile
  puts "\nLick file\n\n  #{lfile}\n\ndoes not exist !"
  puts "\nCreating it with a single sample lick and"
  puts "lots of comments explaining the format."
  puts
  puts "However, you need to add more licks yourself,"
  puts "to make this mode (licks) really useful."
  puts
  FileUtils.cp('resources/sample_licks_with_holes.txt', lfile)
  FileUtils.cp('recordings/juke.mp3', $lick_dir + '/recordings') 
  if $opts[:testing]
    File.open(lfile, 'a') do |f|
      f.write <<~end_of_content

        [default]
          tags = testing

        [one]
          holes = +1 +1 -1

        [two] 
          holes = +1 +1 -1 +1
          
        [three]
          holes = +1 +1 -1

        [long]
          holes = -1 -1 -1 -1 -1 -1 -1 -1 -2+3 -2+3 -2+3 -2+3 -2+3 -2+3 -2+3 -2+3 -3 -3 -3 -3 -3 -3 -3 -3 -3 -4 -4 -4 -4 -4 -4 -5 -5 -5 -5 -5 -5 -5 -5 -6 -6 -6 -6 -6 -6 -6 -6 -6 -6 -7 -7 -7 -7 -7 -7 -7 -8 -8 -8 -8 -8 -8 -8 -8 -8 -8 -8 -9 -9 -9 -9 -9 -9 -9 -9 -9 -9 -10 -10 -10 -10 -10 -10 -10 -10 -10
          rec = juke.mp3
          rec.start = 2.2
          rec.length = 4

        end_of_content
    end
  end
  puts "Now you may try again with a few predefined licks (e.g. 'juke') ..."
  puts "...and then add some of your own to make this feature useful !\n\n"
end


def get_lick_file
  FileUtils.mkdir_p($lick_dir) unless File.directory?($lick_dir)
  FileUtils.mkdir_p($lick_dir + '/recordings') unless File.directory?($lick_dir + '/recordings')

  glob = $lick_file_template % '{holes,notes}'
  lfiles = Dir[glob]
  err "There are two files matching #{glob}; please check and remove one" if lfiles.length > 1
  if lfiles.length == 0
    lfile = $lick_file_template % 'holes'
    create_initial_lick_file lfile
    exit
  else
    lfile = lfiles[0]
  end
  lfile
end


def refresh_licks
  if File.mtime($lick_file) > $lick_file_mod_time
    $all_licks, $licks = read_licks
    true
  else
    false
  end
end


def musical_event? hole_or_note
  hole_or_note.match?(/^\(\S*\)$/)
end


def print_lick_and_tag_info all_licks = $all_licks, licks = $licks

  puts "\n(read from #{$lick_file})\n\n"

  if licks
    puts "\nInformation about licks selected by tags and hole-count only\n"
    puts "============================================================\n\n"
    print_licks_by_tags licks
  end
  
  puts "\n\nInformation about all known licks, disregarding tags and hole count\n"
  puts "===================================================================\n\n"
  print_licks_by_tags all_licks
  puts
  
  # stats for tags
  puts "All tags:\n\n"
  counts = Hash.new {|h,k| h[k] = 0}
  all_licks.each do |lick|
    lick[:tags].each {|tag| counts[tag] += 1}
  end
  long_text = 'Total number of different tags:'
  maxlen = [long_text.length,counts.keys.max_by(&:length).length].max
  format = "  %-#{maxlen}s %6s\n"
  line = ' ' + '-' * (maxlen + 10)
  printf format,'Tag','Count'
  puts line
  counts.keys.sort.each {|k| printf format,k,counts[k]}
  puts line
  printf format, 'Total number of tags:', counts.values.sum
  printf format, long_text, counts.keys.length
  puts line
  printf format, 'Total number of licks: ',all_licks.length

  # stats for lick lengths
  puts "\nCounting licks by number of holes:\n"  
  format = "  %2d ... %2d     %3d\n"
  line = "  ----------    ---------------"
  puts "\n  Hole Range    Number of Licks"
  puts line
  by_len = all_licks.group_by {|l| l[:holes].length}
  cnt = 0
  lens = []
  by_len.keys.sort.each_with_index do |len,idx|
    cnt += by_len[len].length
    lens << len
    if cnt > all_licks.length / 10 || ( idx == by_len.keys.length && cnt > 0)
      printf format % [lens[0],lens[-1],cnt]
      cnt = 0
      lens = []
    end
  end
  printf format % [lens[0],lens[-1],cnt] if lens.length > 0
  puts line
  puts format % [by_len.keys.minmax, all_licks.length].flatten
  puts
end


def replace_vars vars, words, name
  words.map do |word|
    if word.start_with?('$')
      err("Unknown variable #{word} used in lick #{name}") unless vars[word]
      vars[word]
    else
      word
    end
  end
end


def get_last_lick_idxs_from_journal licks = $licks
  lnames = []
  File.readlines($journal_file).each do |line|
    md = line.match(/^Lick +([^, :\/]+)/)
    lnames << md[1] if md
    lnames.shift if lnames.length > 100
  end
  err "Did not find any licks in #{$journal_file}" unless lnames.length > 0
  idxs = lnames.map do |ln|
    licks.index {|l| l[:name] == ln }
  end.select(&:itself)
  err "Could not find any of the lick names #{lnames} from #{$journal_file} among current set of licks #{licks.map {|l| l[:name]}}" if idxs.length == 0
  idxs.reverse[0..16]
end


def print_last_licks_from_journal licks = $licks
  puts "\nList of most recent licks played:"
  puts "  - abbrev (e.g. '2l') for '--start-with'"
  puts "  - name  tag1,tag2, ... of lick"
  puts
  puts "Last lick comes first:"
  puts
  cnt = 1
  get_last_lick_idxs_from_journal(licks).each do |idx|
    print '  '
    if cnt == 1
      print ' l: '
    elsif cnt <= 9
      print cnt.to_s + 'l: '
    else
      print '    '
    end
    cnt += 1
    puts licks[idx][:name]
    
  end
  puts
  puts "(from #{$journal_file})"
  puts
end


def print_licks_by_tags licks
  ltags = tags = nil
  puts "All licks with their tags:"
  puts
  print '  '
  licks.each do |lick|
    tags = lick[:tags].join(',')
    if ltags && ltags != tags
      print " ..... #{ltags}\n  "
    else
      print ',' if ltags
    end
    print lick[:name]
    ltags = tags
  end
  puts " ..... #{ltags}"
  puts "\n  Total number of licks:   #{licks.length}\n"
end
