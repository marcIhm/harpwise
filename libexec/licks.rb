#
# Handling of licks
#


$lick_file_mod_time = nil
$lick_file = nil

def read_licks graceful: false, lick_file: nil, use_opt_lick_prog: true
  # argument lick_file is used in tests

  $lick_file = lfile = ( lick_file || get_lick_file )
  $lick_file_mod_time = File.mtime($lick_file)

  # directory may just have been created when getting lick_file
  File.write($star_file, YAML.dump(Hash.new)) unless File.exist?($star_file)
  ($starred = Hash.new {|h,k| h[k] = 0}).merge! yaml_parse($star_file)
  all_licks = []
  licks = nil
  derived = []
  name2prog = Hash.new
  name2lick = Hash.new
  default = Hash.new
  vars = Hash.new
  sec_title = sec_type = nil
  section = nil

  type2keys = { lick: %w(holes notes tags tags.add desc desc.add rec rec.key rec.start rec.length),
                default: %w(tags tags.add desc desc.add rec.key),
                vars: [],
                prog: %w(desc licks tags) }
      
  #
  # Proces file line by line
  #
  (File.readlines(lfile) << '[default]').each_with_index do |line, idx|  ## trigger processing of last lick at end of file

    lno = idx + 1
    line.chomp!
    line.gsub!(/#.*/,'')
    line.strip!
    next if line == ''
    derived << line
    where = "file #{lfile}, line #{lno}"
      
    if md = ( line.match(/^\[(#{$word_re})\]$/) ||
              line.match(/^\[(prog #{$word_re})\]$/) )
      derived.insert(-2,'')

      # starting new section, process old section first

      # sec_type, lick, etc. still belong to previous lick
      if sec_type == :default
        default = section
      elsif sec_type == :vars
        # vars have already been assigned; nothing to do here
      elsif sec_type == :prog
        err "Section 'prog #{sec_title}' needs to contain key 'licks' (#{where})" unless section[:licks]
        before = name2prog[sec_title]
        err "Progression '#{sec_title}' appeares at least twice in #{lfile}: first on line #{before[:lno]} and again on line #{section[:lno]}" if before
        section[:tags] ||= []
        name2prog[sec_title] = section
        err "Progression #{sec_title} does not contain any licks" unless section[:licks]
        $name_collisions_mb[sec_title] << 'lick-progression'
      elsif sec_type == :lick
        # a lick
        before = name2lick[sec_title]
        err "Lick '#{sec_title}' appeares at least twice in #{lfile}: first on line #{before[:lno]} and again on line #{section[:lno]}" if before
        name2lick[sec_title] = section
        all_licks << process_lick(section, sec_title, vars, default)
        $name_collisions_mb[sec_title] << 'lick'
      end
      
      # Start with new section
      sec_title = md[1]
      section = Hash.new
      section[:lno] = lno
      
      if sec_title == 'default'
        sec_type = :default
      elsif sec_title == 'vars'
        # vars have already been assigned; nothing to do here
        sec_type = :vars
      elsif md = sec_title.match(/^prog (#{$word_re})$/)
        sec_type = :prog
        sec_title = section[:name] = md[1]
      else
        sec_type = :lick    
        section[:name] = sec_title
      end

      # helpful for dumps
      section[:type] = sec_type
      
    # [empty section]
    elsif line.match?(/^ *\[\] *$/)
      err "Section [] cannot be empty (#{where})"

    # [non-word]
    elsif md = line.match(/^ *\[(.*)\] *$/)
      err "Invalid section name: '#{md[1]}', only letters, numbers, underscore and minus are allowed (#{lfile}, line #{lno})"
      
    # Assign variable like, $var = value
    elsif md = line.match(/^ *(\$#{$word_re}) *= *(.*) *$/)
      var, value = md[1..2]
      err "Variable assignment (here: #{var}) is not allowed outside a [var]-section; this section is [#{section}] (#{where})" if sec_type != :vars 
      vars[var] = value
      
    # tags
    elsif (md = line.match(/^ *(tags.add) *= *(.*?) *$/))||
          (md = line.match(/^ *(tags) *= *(.*?) *$/))
      key, tags = md[1, 2]
      skey = key.o2sym2
      check_section_key(sec_type, key, section, type2keys, where)
      section[skey] = tags.split
      section[skey].each do |tag|
        err "Tags must consist of word characters; '#{tag}' (#{where}) does not" unless tag.match?(/^#{$word_re}$/) || tag.match?(/^\$#{$word_re}$/) 
      end
      
    # holes = value1 value2 ...
    elsif md = line.match(/^ *holes *= *(.*?) *$/)
      check_section_key(sec_type, 'holes', section, type2keys, where)
      holes = md[1]
      section[:holes] = holes.split.map do |hole|
        err("Hole '#{hole}' is not among holes of harp #{$harp_holes} (#{where})") unless musical_event?(hole) || $harp_holes.include?(hole)
        hole
      end
      err "Lick #{sec_title} key 'holes' is empty (#{where})" unless section[:holes].length > 0
      section[:holes_wo_events] = section[:holes].reject {|h| musical_event?(h)}
      derived[-1] = "  notes = " + holes.split.map do |hoe|
        musical_event?(hoe)  ?  hoe  :  $harp[hoe][:note]
      end.join(' ')
      
    # notes = value1 value2 ...
    elsif md = line.match(/^ *notes *= *(.*?) *$/)
      check_section_key(sec_type, 'notes', section, type2keys, where)
      notes = md[1]
      # do not keep notes, but rather convert them to holes right away
      section[:holes] = notes.split.map do |note|
        err("Note '#{note}' is not among notes of harp #{$harp_notes} (#{where})") unless musical_event?(note) || $harp_notes.include?(note)
        $note2hole[note]
      end
      err "Lick '#{sec_title}', key 'notes' is empty (#{where})" unless section[:holes].length > 0
      derived[-1] = "  holes = " + lick['holes'].join(' ')

    # desc.add = multi word description
    # desc = multi word description
    elsif (md = line.match(/^ *(desc) *= *(.*?) *$/)) ||
          (md = line.match(/^ *(desc.add) *= *(.*?) *$/))
      key, desc = md[1 .. 2]
      check_section_key(sec_type, key, section, type2keys, where)
      section[key.o2sym2] = desc

    # rec = mp3
    elsif md = line.match(/^ *rec *= *(#{$word_re}) *$/)
      check_section_key(sec_type, 'rec', section, type2keys, where)
      file = $lick_dir + '/recordings/' + md[1]
      err "File #{file} does not exist (#{where})" unless File.exist?(file)
      section[:rec] = md[1]

    # rec.key = musical-key
    elsif md = line.match(/^ *rec.key *= *(#{$word_re}) *$/)
      check_section_key(sec_type, 'rec.key', section, type2keys, where)
      mkey = md[1]
      err "Unknown musical key '#{mkey}'; none of: #{$conf[:all_keys].join(',')} (#{where})" unless $conf[:all_keys].include?(mkey)
      section[:rec_key] = mkey

    # rec.start = secs or rec.length = secs
    elsif md = (line.match(/^ *(rec.start) *= *(.*?)$ *$/) || line.match(/^ *(rec.length) *= *(.*?)$ *$/))
      check_section_key(sec_type, 'rec.key', section, type2keys, where)
      key, val = md[1..2]
      begin
        Float(val)
      rescue ArgumentError
        err "Value of #{key} is not a number: '#{val}' (#{where})"
      end
      section[key.o2sym2] = val
    elsif md = line.match(/^ *tag *= *(#{$word_re}) *$/)
      check_section_key(sec_type, 'tag', section, type2keys, where)
      section[:tag] = md[1]

    elsif md = line.match(/^ *licks *= *(.*?) *$/)
      check_section_key(sec_type, 'licks', section, type2keys, where)
      section[:licks] = md[1].split

    # all assignments, that have not been handled before
    elsif md = line.match(/^ *(#{$word_re}) *= *(#{$word_re}) *$/)
      key = md[1]
      check_section_key(sec_type, key, section, type2keys, where)
      err "Internal error: not expected to come here"

    else
      err "Cannot parse this line:\n\n#{line}\n\na line should be one of:\n  - a comment starting with '#'\n  - a section like '[name]'\n  - an assignment like 'key = something'\n(#{where})"
    end

  end  ## end of processing lines in file

  err("No licks found in #{lfile}") unless all_licks.length > 0 

  # check for duplicate licks
  h2n = Hash.new {|h,k| h[k] = Array.new}
  all_licks.each do |lick|
    next if lick[:tags].include?('dup')
    h2n[lick[:holes].reject {|h| musical_event?(h)}] << lick[:name]
  end
  h2n = h2n.to_a.select {|p| p[1].length > 1}.to_h
  err "Some hole-sequences appear under more than one name: #{h2n.inspect} ! (add tag 'dup' to avoid this error) (file #{lfile})" if h2n.length > 0

  # check progressions and add info
  name2prog.keys.each do |pname|
    err "There is progression and a lick both with name '#{pname}'" if name2lick[pname]
    name2prog[pname][:licks].each do |lname|
      err "Lick progression '#{pname}' contains unknown lick #{lname} (file #{lfile})" unless name2lick[lname]
      name2lick[lname][:progs] << pname
    end
  end
  
  # write derived lick file
  dfile = $derived_dir + '/derived_' + File.basename(lfile).sub(/holes|notes/, lfile['holes'] ? 'notes' : 'holes')
  File.open(dfile,'w') do |df|
    df.write <<~end_of_content
    
         #
         # derived lick file with #{dfile['holes'] ? 'holes' : 'notes'}
         # created from #{lfile}
         #
           
         end_of_content
    df.puts derived.join("\n") + "\n"
  end

  if $adhoc_lick_prog
    name2prog['adhoc'] = { lno: 1,
                           desc: "Adhoc lick progression given on the commandline",
                           licks: $adhoc_lick_prog }
    $adhoc_lick_prog.each {|lname| name2lick[lname][:progs] << 'adhoc'}
  end
   
  if $opts[:lick_prog] && use_opt_lick_prog
    prog  = name2prog[$opts[:lick_prog]]
    err "Unknown lick-progression '#{$opts[:lick_prog]}', none of: #{name2prog.keys.join(',')}" unless prog
    licks = prog[:licks].map {|lnm| name2lick[lnm]}
    $opts[:iterate] = :cycle
    
  else
    
    # keep only those licks, that match any of the four --tags arguments
    keep_all = Set.new($opts[:tags_all]&.split(','))
    keep_any = Set.new($opts[:tags_any]&.split(','))
    drop_all = Set.new($opts[:drop_tags_all]&.split(','))
    drop_any = Set.new($opts[:drop_tags_any]&.split(','))
    
    if (keep_all).intersection(drop_any).any?
      if graceful
        return [[],[]]
      else
        err "No licks can be found, because options '--tags-all' and '--drop-tags-any' have this intersection: #{(keep_all).intersection(drop_any).to_a}"
      end
    end

    tags_licks = Set.new(all_licks.map {|l| l[:tags]}.flatten)
    # add special tags right now, the licks only below
    tags_licks << 'journal' if journal_length > 0
    tags_licks << 'adhoc' if $adhoc_lick_holes
    
    [['--tags-all', keep_all],
     ['--tags-any', keep_any],
     ['--dtop-tags-all', drop_all],
     ['--drop-tags-any', drop_any]].each do |opt, tags|
      if !tags.subset?(tags_licks)
        if graceful
          return [[],[]]
        else
          print "\nTags known either from lick-file\n#{lfile}\nor added by harpwise:\n\n"
          print_in_columns tags_licks.to_a.sort, pad: :tabs
          err "Among tags from option #{opt} (#{tags.to_a.join(', ')}), these are unknown: #{(tags - tags_licks).to_a.join(', ')}; therefore no licks are selected. (see above for a list of all tags)."
        end
      end
    end
    
    # apply all filtering options in order
    licks = all_licks.
              select {|lick| keep_all.empty? || (keep_all.subset?(Set.new(lick[:tags])))}.
              select {|lick| keep_any.empty? || (keep_any.to_a & lick[:tags]).any?}.
              reject {|lick| drop_all.any? && (drop_all.subset?(Set.new(lick[:tags])))}.
              reject {|lick| drop_any.any? && (drop_any.to_a & lick[:tags]).any?}.
              select {|lick| lick[:holes].length <= ( $opts[:max_holes] || 1000 )}.
              select {|lick| lick[:holes].length >= ( $opts[:min_holes] || 0 )}

    # insert journal as lick
    if journal_length > 0
      lick = { name: 'journal',
               lno: 1,
               desc: "The current journal as a lick; see also #{$journal_file}",
               holes: $journal.clone,
               tags: %w(journal) }
      lk = process_lick(lick, 'journal', vars, default)
      all_licks << lk
      licks << lk
    end

    # handle adhoc lick from commandline
    if $adhoc_lick_holes
      lick = { name: 'adhoc',
               lno: 1,
               desc: 'Lick given on the commandline',
               holes: $adhoc_lick_holes.map do |hon|
                 ( $harp_holes.include?(hon) && hon ) ||
                   $note2hole[hon] ||
                   err("Given note #{hon} cannot be played on this harmonica")
               end,
               tags: %w(adhoc) }
      lk = process_lick(lick, 'adhoc', vars, default)
      all_licks << lk
      licks << lk
    end

    err("None of the #{all_licks.length} licks from #{lfile} has been selected when applying these tag-options: #{desc_lick_select_opts}") if licks.length == 0

  end  ## $opts[:lick_prog]

  [all_licks, licks, name2prog]

end


def create_initial_lick_library lfile
  if $type == 'richter'
    puts "\n\n\e[32mLICK FILE\e[0m\n\n  #{lfile}\n\ndoes not exist !"
    puts "\nCreating it with five sample licks and loads of comments,"
    puts "explaining the format."
    puts
    puts "However, you need to add more licks yourself, to make"
    puts "this mode (licks) really useful."
    puts
    puts "\n\e[32mON GETTING MORE LICKS\e[0m\n\n"
    lick_sources = ERB.new(IO.read("#{$dirs[:install]}/resources/lick_sources.txt")).result(binding).lines
    lick_sources.pop while lick_sources[-1].strip.empty?
    File.write(lfile, ERB.new(IO.read("#{$dirs[:install]}/resources/sample_licks_with_holes_richter.txt")).result(binding))
    lick_sources.each {|l| print l}
    %w(wade.mp3 st-louis.mp3 feeling-bad.mp3).each do |file|
      FileUtils.cp("#{$dirs[:install]}/recordings/#{file}", $lick_dir + '/recordings')
    end
    puts
    puts "\n\e[32mGO AHEAD, some sample licks have been created.\e[0m\n\n"
    puts 'Now you may try again with three predefined licks:'
    puts
    puts ' - Wade in the Water'
    puts ' - St. Louis Blues'
    puts ' - Going down that road feeling bad'
    puts
    puts "(all in my own, rather imperfect recording...)"
    puts "If you like this mode and want to make it more useful,"
    puts "then consider adding more licks to:"
    puts "#{lfile}"
    puts "(where you may also reread these and more suggestions)"
    puts
  else
    puts "\n\n\e[32mLICK FILE\e[0m\n\n  #{lfile}\n\ndoes not exist !\n\n"
    puts "Creating an empty initial version for type '#{$type}'.\n\n"
    try_richter = ERB.new(IO.read("#{$dirs[:install]}/resources/try_richter.txt")).result(binding).lines
    try_richter.pop while try_richter[-1].strip.empty?
    File.write(lfile, ERB.new(IO.read("#{$dirs[:install]}/resources/sample_licks_with_holes_other.txt")).result(binding))
    try_richter.each {|l| print l}
    puts "\nNow you may try again."
    puts
  end
end


def get_lick_file
  FileUtils.mkdir_p($lick_dir) unless File.directory?($lick_dir)
  FileUtils.mkdir_p($lick_dir + '/recordings') unless File.directory?($lick_dir + '/recordings')

  glob = $lick_file_template % '{holes,notes}'
  lfiles = Dir[glob]
  err "There are two files matching #{glob}; please check and remove one" if lfiles.length > 1
  if lfiles.length == 0
    lfile = $lick_file_template % 'holes'
    create_initial_lick_library lfile
    exit
  else
    lfile = lfiles[0]
  end
  lfile
end


def refresh_licks
  if File.mtime($lick_file) > $lick_file_mod_time
    $all_licks, $licks, $all_lick_progs = read_licks
    true
  else
    false
  end
end


def musical_event? hole_or_note, type = :general
  has_paren = hole_or_note[0] == '(' && hole_or_note[-1] == ')'
  has_brack = hole_or_note[0] == '[' && hole_or_note[-1] == ']'
  has_head = hole_or_note.match?(/^(\.|~)\w*$/)
  is_comma = hole_or_note == ','
  case type
  when :general
    return has_paren || has_brack || has_head || is_comma
  when :secs
    return false unless has_paren
    return false unless hole_or_note[-2] == 's' 
    return ( !!Float(hole_or_note[1 .. -3]) rescue false )
  else
    err "Internal error: #{type}"
  end
end


def get_musical_duration hole_or_note
  duration = ( $opts[:fast]  ?  0.5  :  1.0)
  return duration unless musical_event?(hole_or_note)
  return duration unless hole_or_note[-2 .. -1] == 's)'
  begin
    return Float(hole_or_note[1 .. -3])
  rescue
    return duration
  end
end


def replace_vars vars, strings, name
  strings.map do |string|
    string_orig = string
    while md = string.match(/^(.*?)\$(#{$word_re})(.*?)$/)
      word = '$' + md[2]
      err("Unknown variable '#{word}' used in string '#{string_orig}' for lick #{name}; it is not in #{vars}") unless vars[word]
      string = md[1] + vars[word] + md[3]
    end
    err "This string contains a '$'-sign, but cannot be handled as a variable: '#{string}'; lick is #{name}" if string['$']

    string
  end
end

def desc_lick_select_opts indent: ''

  effective = []
  relax = []
  [:tags_all, :tags_any, :drop_tags_all, :drop_tags_any, :max_holes, :min_holes].each do |opt|
    if $opts[opt] && $opts[opt].to_s.length > 0
      effective << "\n#{indent}  --" + opt.o2str + ' ' + $opts[opt].to_s
      relax << "--#{opt.o2str} -"
    end
  end
  effective << "\n#{indent}no lick-selecting option or config in effect" if effective.length == 0
  effective.join + "\n#{indent}(some of these may come from config" +
    if relax.length == 0
      ")\n"
    else
      "; relax them with:   #{relax.join('   ')}  )\n"
    end
end


def process_lick lick, name, vars, default
  err "Lick #{name} does not contain any holes" unless lick[:holes]  
  # merge from star-file
  star_tag = if $starred.keys.include?(name)
               if $starred[name] > 0
                 ['starred']
               elsif $starred[name] < 0
                 ['unstarred']
               end
             end || []
  
  lick[:tags] = replace_vars(vars,
                             ([lick[:tags] || default[:tags]] +
                              [lick[:tags_add] || default[:tags_add]] +
                              star_tag
                             ).flatten.compact,name).sort.uniq
  lick[:tags] << ( lick[:rec]  ?  'has_rec'  :  'no_rec' )
  
  lick[:desc] = lick[:desc] || default[:desc] || ''
  if lick[:desc_add] && lick[:desc_add].length > 0
    lick[:desc] += ' ' + lick[:desc_add] 
  elsif default[:desc_add] && default[:desc_add].length > 0
    lick[:desc] += ' ' + default[:desc_add] 
  end
  lick[:desc] = replace_vars(vars,[lick[:desc].strip],name)[0]
  lick[:rec_key] ||= ( default[:rec_key] || 'c' )
  lick[:rec_key] = replace_vars(vars,[lick[:rec_key]],name)[0]

  $licks_semi_shifts.keys.select {_1 > 0}.each do |st|
    tag = $licks_semi_shifts[st]
    num_shiftable = lick[:holes].inject(0) do |sum, hole|
      sum + ( musical_event?(hole)  ?  1  :
                ( $harp[hole][:shifted_by][st]  ?  1  :  0 ) )
    end
    lick[:tags] << tag if lick[:holes].length == num_shiftable
  end
  lick[:progs] = []
  lick
end


def check_section_key type, key, section, type2keys, where

  # first, check for double key in section
  skey = key.o2sym2
  err "Key '#{key}' (below [#{section[:name]}], #{where}) has already been defined" if section[skey]

  # now for allowed keys in section
  err "Assigning a key (here: #{key}) is not allowed before first section, e.g. #{type2keys.keys.map(&:o2str).join(',')} #{where}" unless type
  return if type2keys[type].include?(key)
  others = type2keys.keys.select {|type| type2keys[type].include?(key)}.map(&:o2str)
  what = case type
         when :lick
           "lick '#{section[:name]}'"
         when :prog
           "prog '#{section[:name]}'"
         when :default
           "default-section"
         when :vars
           "vars-section"
         else
           err "Internal error: unkown type: #{type}"
         end
  err(
    if others.length > 0
      "Key  '#{key}'  is not allowed:\n  - The current section has been identified as #{what}\n    and key '#{key}' is not allowed there\n  - However, key '#{key}' may appear in these types of section:   #{others.join(', ')}\n  - On the other hand, for section of type #{type}, these keys are allowed:   #{type2keys[type].join(', ')}\n#{where}"
    else
      "Key '#{key}' is unknown for #{what} and any other type of section (#{where})"
    end)
end


def find_lick_by_name name
  nm_idx = $licks.each_with_index.find {|l,idx| l[:name] == name}
  if nm_idx
    return nm_idx[1]
  else
    puts "Unknown lick #{name}, none of:"
    print_in_columns($licks.map {|l| l[:name]}.sort, indent: 4, pad: :tabs)
    puts
    if $licks == $all_licks
      puts "where set of licks has not been restricted by tags"
    else
      puts "after applying these options: #{desc_lick_select_opts}"
    end
    err "Unknown lick: '#{name}' (among #{$licks.length} licks), see above for details"
  end
end


def process_opt_lick_prog
  # make sure, that $opts[:lick_prog] contains the name of a defined
  # lick-progression or 'adhoc' if given initially as a comma-separated list.
  # Make sure, that following rereads give the same result.
  
  # We assume, that licks have already been read with use_opt_lick_prog: false
  $all_licks || err('Internal error: licks not read before')

  # this already errs out for lnames.length > 0 && lpnames.length > 0
  _, _, lnames, lpnames, _, _ = partition_for_mode_or_amongs($opts[:lick_prog].split(','),
                                                          amongs: [:lick, :lick_prog],
                                                          extra_allowed: false)
  if ( lnames.length == 0 && lpnames.length == 0 ) ||
     ( lnames.length > 0  && lpnames.length > 0 )
    err "Internal error, should have had error already in partition: #{lpnames}, #{lnames}"
  elsif lnames.length > 0
    $opts[:lick_prog] = 'adhoc'
    $adhoc_lick_prog = lnames
    $msgbuf.print "Adhoc lick progression", 5, 5, :lick_prog
  else  ## lpnames.length > 0
    err("Can handle only one lick-progression at a time, not: #{lpnames.join(',')}") if lpnames.length > 1
    lnames = $all_lick_progs[lpnames[0]][:licks]
    desc = $all_lick_progs[lpnames[0]][:desc]
    $msgbuf.print "Lick prog #{lpnames[0]}" + ( desc  ?  ", #{desc}"  :  '' ),
                  7, 7, :lick_prog, wrap: true, truncate: false
  end
  
  lnames
end
