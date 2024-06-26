#
# Handling of licks
#


$lick_file_mod_time = nil
$lick_file = nil

def read_licks graceful = false

  $lick_file = lfile = get_lick_file
  $lick_file_mod_time = File.mtime($lick_file)
  all_keys = %w(holes notes rec rec.start rec.length rec.key tags tags.add desc desc.add)

  # directory may just have been created when getting lick_file
  File.write($star_file, YAML.dump(Hash.new)) unless File.exist?($star_file)
  ($starred = Hash.new {|h,k| h[k] = 0}).merge! yaml_parse($star_file)
  all_licks = []
  licks = nil
  derived = []
  adhoc_tag2licks = Hash.new
  all_lick_names = Set.new
  default = Hash.new
  vars = Hash.new
  lick = name = nil
  jrlick = ahlick = nil

  # insert journal as lick
  if journal_length > 0
    all_lick_names << 'journal'
    jrlick = Hash.new
    jrlick[:name] = 'journal'
    jrlick[:lno] = 1
    jrlick[:desc] = "The current journal as a lick; see also #{$journal_file}"
    jrlick[:holes] = $journal.clone
    jrlick[:tags] = ['journal', 'not-from-lickfile']
  end

  
  # handle adhoc lick from commandline
  if $opts[:adhoc_lick]
    all_lick_names << 'adhoc'
    ahlick = Hash.new
    ahlick[:name] = 'adhoc'
    ahlick[:lno] = 1
    ahlick[:desc] = "Lick given on the commandline via --adhoc-lick"
    holes = $opts[:adhoc_lick].strip.split(/\s+|,/)
    holes.each do |hole|
      err "Hole '#{hole}' from '--adhoc-lick=#{$opts[:adhoc_lick]}' is not a hole of a #{$type}-harp: #{$harp_holes.join(',')}" unless $harp_holes.include?(hole)
    end
    ahlick[:holes] = holes
    ahlick[:tags] = ['adhoc', 'from-commandline']
  end

  special_licks = [jrlick, ahlick]
  
  
  (File.readlines(lfile) << '[default]').each_with_index do |line, idx|  # trigger checks for new lick even at end of file
    err "Line #{idx} from #{lfile} is not in a valid encoding for current locale (consider using UTF-8): '#{line}'" unless line.valid_encoding?
    line.chomp!
    line.gsub!(/#.*/,'')
    line.strip!
    next if line == ''
    derived << line


    # adding adhoc-tags to licks
    if md = line.match(/^ *add.tag.to *= *(.*)$/)
      if name
        err "Variable 'add.tag.to' may only appear before first group"
      else
        words = md[1].split(' ').map(&:strip)
        adhoc_tag2licks[words[0]] = words[1 ...]
      end
      

    # start new lick or default or vars
    elsif md = line.match(/^\[(#{$word_re})\]$/)
      derived.insert(-2,'') # empty line before in derived
      nname = md[1]

      
      # Do final processing of previous lick: merging with default and
      # replacement of vars; also collect journal and adhoc, if
      # prepared
      [lick, special_licks].flatten.compact.each do |lick|  ## shadow variable lick deliberately
        if name == 'default'
          default = lick
        elsif name == 'vars'
          # vars have already been assigned; nothing to do here
        else
          err "Lick [#{name}] does not contain any holes" unless lick[:holes]  
          # merge from star-file
          starred = if $starred.keys.include?(name)
                      if $starred[name] > 0
                        ['starred']
                      elsif $starred[name] < 0
                        ['unstarred']
                      end
                    end || []
                        
          lick[:tags] = replace_vars(vars,
                                     ([lick[:tags] || default[:tags]] +
                                      [lick[:tags_add] || default[:tags_add]] +
                                      starred
                                     ).flatten.compact,name).sort.uniq
          lick[:tags] << ( lick[:rec]  ?  'has_rec'  :  'no_rec' )
          adhoc_tag2licks.keys.each do |tag| 
            lick[:tags] << tag if adhoc_tag2licks[tag].include?(name)
          end
          
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

          all_licks << lick
        end
      end
      name = nname
      special_licks = nil

      # start with new lick
      unless %w(default vars).include?(nname)
        err "Lick '#{nname}' has already appeared before (#{lfile}, again on line #{idx + 1})" if all_lick_names.include?(name)
        all_lick_names << nname
      end
      lick = Hash.new
      lick[:name] = nname
      lick[:lno] = idx + 1

      
    # [empty section]
    elsif line.match?(/^ *\[\] *$/)
      err "Lick name [] cannot be empty (#{lfile}, line #{idx + 1})"

      
    # [invalid section]
    elsif md = line.match(/^ *\[(.*)\] *$/)
      err "Invalid lick name: '#{md[1]}', only letters, numbers, underscore and minus are allowed (#{lfile}, line #{idx + 1})"

      
    # $var = value
    elsif md = line.match(/^ *(\$#{$word_re}) *= *(.*) *$/)
      var, value = md[1..2]
      err "Variables (here: #{var}) may only be assigned in section [vars]; not in [#{name}] (#{lfile}, line #{idx + 1})" unless name == 'vars'
      vars[var] = value

      
    # tags.add = value1 value2 ...
    # tags = value1 value2 ...
    elsif (md = line.match(/^ *(tags.add) *= *(.*?) *$/))||
          (md = line.match(/^ *(tags) *= *(.*?) *$/))
      var, tags = md[1 .. 2]
      svar = var.gsub('.','_').to_sym
      err "Key '#{var}' (below [#{name}]) has already been defined" if lick[svar]
      lick[svar] = tags.split
      lick[svar].each do |tag|
        err "Tags must consist of word characters; '#{tag}' (below [#{name}]) does not" unless tag.match?(/^#{$word_re}$/) || tag.match?(/^\$#{$word_re}$/) 
      end

      
    # holes = value1 value2 ...
    elsif md = line.match(/^ *holes *= *(.*?) *$/)
      err "Key 'holes' (below [#{name}]) has already been defined" if lick[:holes]
      holes = md[1]
      err "File #{lfile} should only contain key 'notes', not 'holes' (below [#{name}])" if lfile['notes']
      lick[:holes] = holes.split.map do |hole|
        err("Hole '#{hole}' in lick #{name} from #{lfile} is not among holes of harp #{$harp_holes}") unless musical_event?(hole) || $harp_holes.include?(hole)
        hole
      end
      err "Lick #{name} does not contain any holes (#{lfile}, line #{idx + 1})" unless lick[:holes].length > 0
      lick[:holes_wo_events] = lick[:holes].reject {|h| musical_event?(h)}
      derived[-1] = "notes = " + holes.split.map do |hoe|
        musical_event?(hoe)  ?  hoe  :  $harp[hoe][:note]
      end.join(' ')

      
    # notes = value1 value2 ...
    elsif md = line.match(/^ *notes *= *(.*?) *$/)
      err "Key 'notes' (below [#{name}]) has already been defined" if lick[:notes]
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
      svar = var.gsub('.','_').to_sym
      err "Key '#{var}' (below [#{name}]) has already been defined" if lick[svar]
      lick[svar] = desc
      

    # rec.key = musical-key
    elsif md = line.match(/^ *rec.key *= *(#{$word_re})$ *$/)
      mkey = md[1]
      err "Key 'rec.key' (below [#{name}]) has already been defined" if lick[:rec_key]
      err "Unknown musical key '#{mkey}'; none of #{$conf[:all_keys]}" unless $conf[:all_keys].include?(mkey)
      lick[:rec_key] = mkey

    # all assignments, that have not been handled above
    elsif md = line.match(/^ *(#{$word_re}) *= *(-?#{$word_re}) *$/)
      key, value = md[1..2]
      if name == 'default'
        # assignment for these keys has been handled before
        err "Default section only allows keys tags, tags.add, desc, desc.add, rec_key ; not '#{key}'"
      elsif name == 'vars'
        # variable assignments have been handled before
        err "Section [vars] may only contain variables (starting with '$'), not #{key} (#{lfile}, line #{idx + 1})"
      # normal lick
      else
        # desc, tags, holes, etc. have already been handled above special
        if %w(rec.start rec.length).include?(key)
          begin
            Float(value)
          rescue ArgumentError
            err "Value of #{key} is not a number: '#{value}' (#{lfile}, line #{idx + 1})"
          end
        end

        if key == 'rec.start' && value.to_f < 0
          err "Value of rec.start cannot be negative: '#{value}' (#{lfile}, line #{idx + 1})"
        end
        
        if all_keys.include?(key)
          skey = key.gsub('.','_').to_sym
          err "Key '#{key}' (below [#{name}]) has already been defined" if lick[skey]
          lick[skey] = value
        else
          err "Unknown key '#{key}', none of #{all_keys}"
        end
        
        if key == 'rec'
          file = $lick_dir + '/recordings/' + value
          err "File #{file} does not exist" unless File.exist?(file)
        end
      end


    else
      err "Cannot parse this line: '#{line}' (#{lfile}, line #{idx + 1})"
    end

  end # end of processing lines in file

  err("No licks found in #{lfile}") unless all_licks.length > 0 

  # check for duplicate licks
  h2n = Hash.new {|h,k| h[k] = Array.new}
  all_licks.each do |lick|
    next if lick[:tags].include?('dup')
    h2n[lick[:holes].reject {|h| musical_event?(h)}] << lick[:name]
  end
  h2n = h2n.to_a.select {|p| p[1].length > 1}.to_h
  err "Some hole-sequences appear under more than one name: #{h2n.inspect} ! (add tag 'dup' to avoid this error)" if h2n.length > 0
  
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

  
  if $opts[:licks]

    lick_names = $opts[:licks].split(',')
    licks = all_licks.select {|lick| lick_names.include?(lick[:name])}
    if licks.length != lick_names.length
      err("These licks given in via '--licks' could not be found in #{lfile}: " +
          (lick_names - licks.map {|l| l[:name]}).join(','))
    end
  else
    
    tags_licks = Set.new(all_licks.map {|l| l[:tags] + %w(has_rec no_rec starred shifts_four shifts_five shifts_eight)}.flatten.sort_by(&:to_s))
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

    # maybe sort licks according to add.tag.to
    lnames = licks.map {|l| l[:name]}
    lick_sets_with_all = adhoc_tag2licks.values.
                           select {|lnms| lnames - lnms == []}
    if lick_sets_with_all.length > 0
      licks.sort! do |lk1, lk2|
        lick_sets_with_all[0].index(lk1[:name]) <=> lick_sets_with_all[0].index(lk2[:name])
      end
    end
    
    # insert journal and adhoc if set and not already selected
    lick_names = licks.map {|lick| lick[:name]}
    [jrlick, ahlick].
      compact.
      reject {|lick| lick_names.include?(lick[:name])}.
      each {|lick| licks.unshift(lick)}

    err("None of the #{all_licks.length} licks from #{lfile} has been selected when applying these tag-options:#{desc_lick_select_opts}") if licks.length == 0

  end

  [all_licks, licks]
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
    $all_licks, $licks = read_licks
    true
  else
    false
  end
end


def musical_event? hole_or_note
  (hole_or_note[0] == '(' && hole_or_note[-1] == ')') ||
    (hole_or_note[0] == '[' && hole_or_note[-1] == ']') 
end


def get_musical_duration hole_or_note
  dura = ( $opts[:fast]  ?  0.5  :  1.0)
  return dura unless musical_event?(hole_or_note)
  return dura unless hole_or_note[-2 .. -1] == 's)'
  begin
    return Float(hole_or_note[1 .. -3])
  rescue
    return dura
  end
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

def desc_lick_select_opts
  effective = [:tags_all, :tags_any, :drop_tags_all, :drop_tags_any, :max_holes, :min_holes].map do |opt|
    if $opts[opt] && $opts[opt].to_s.length > 0
      "\n  --" + opt.o2str + ' ' + $opts[opt].to_s
    else
      ''
    end
  end.join + "\n(some of these values may also come from config)\n"
end
