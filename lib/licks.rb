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
  all_lick_names = Set.new
  default = Hash.new
  vars = Hash.new
  lick = name = nil

  # insert journal as lick
  if journal_length > 0
    all_lick_names << 'journal'
    lick = Hash.new
    lick[:name] = 'journal'
    lick[:lno] = 1
    lick[:desc] = "The current journal as a lick; see also #{$journal_file}"
    lick[:holes] = $journal.clone
    lick[:tags] = ['journal', 'not-from-lickfile']
  end
  
  (File.readlines(lfile) << '[default]').each_with_index do |line, idx|  # trigger checks for new lick even at end of file
    line.chomp!
    line.gsub!(/#.*/,'')
    line.strip!
    next if line == ''
    derived << line

    # [start new lick or default or vars]
    if md = line.match(/^\[(#{$word_re})\]$/)
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
                                     ).flatten.select(&:itself),name).sort.uniq

          lick[:desc] = lick[:desc] || default[:desc] || ''
          if lick[:desc_add] && lick[:desc_add].length > 0
            lick[:desc] += ' ' + lick[:desc_add] 
          elsif default[:desc_add] && default[:desc_add].length > 0
            lick[:desc] += ' ' + default[:desc_add] 
          end
          lick[:desc].strip!
          lick[:rec_key] ||= 'c'
          lick[:rec_key] = replace_vars(vars,[lick[:rec_key]],name)[0]

          all_licks << lick
        end
      end
      name = nname

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
    elsif md = line.match(/^ *(\$#{$word_re}) *= *(#{$word_re})$/)
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

    elsif md = line.match(/^ *(#{$word_re}) *= *(-?#{$word_re})$/)
      key, value = md[1..2]
      if name == 'default'
        # correct assignment has been handled before
        err "Default section only allows keys tags, tags.add, desc or desc.add ; not '#{key}'" 
      elsif name == 'vars'
        # correct assignments have been handled before
        err "Section [vars] may only contain variables (starting with '$'), not #{key} (#{lfile}, line #{idx + 1})"
      # normal lick
      else
        # tags, holes and notes have already been handled above special
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
        elsif key == 'rec.key'
          err "Unknown key '#{value}'; none of #{$conf[:all_keys]}" unless $conf[:all_keys].include?(value)
        end
      end
    else
      err "Cannot parse this line: '#{line}' (#{lfile}, line #{idx + 1})"
    end
  end # end of processing lines in file

  err("No licks found in #{lfile}") unless all_licks.length > 0 

  # check for duplicate licks
  h2n = Hash.new {|h,k| h[k] = Array.new}
  all_licks.each do |l|
    h2n[l[:holes].reject {|h| musical_event?(h)}] << l[:name]
  end
  h2n = h2n.to_a.select {|p| p[1].length > 1}.to_h
  err "Some hole-sequences appear under more than one name: #{h2n.inspect}" if h2n.length > 0
  
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
  keep_any = Set.new($opts[:tags_any]&.split(','))
  keep_all = Set.new($opts[:tags_all]&.split(','))
  discard_any = Set.new($opts[:no_tags_any]&.split(','))
  discard_all = Set.new($opts[:no_tags_all]&.split(','))

  all_tag_opts = [$opts[:tags_any], $opts[:tags_all], $opts[:no_tags_any], $opts[:no_tags_all]]

  if (keep_all).intersection(discard_any).any?
    if graceful
      return [[],[]]
    else
      err "No licks can be found, because options '--tags-all' and '--no-tags-any' have this intersection: #{(keep_all).intersection(discard_any).to_a}"
    end
  end

  tags_licks = Set.new(all_licks.map {|l| l[:tags]}.flatten)
  [['--tags-any', keep_any],
   ['--tags-all', keep_all],
   ['--no-tags-any', discard_any],
   ['--no-tags-all', discard_all]].each do |opt, tags|
    if !tags.subset?(tags_licks)
      if graceful
        return [[],[]]
      else
        err "Among tags #{tags.to_a} in option #{opt}, there are some, which are not in lick file #{lfile} #{tags_licks.to_a}; unknown in options are: #{(tags - tags_licks).to_a}"
      end
    end
  end

  licks = all_licks.
            select {|lick| keep_any.empty? || (keep_any.to_a & lick[:tags]).any?}.
            select {|lick| keep_all.empty? || (keep_all.subset?(Set.new(lick[:tags])))}.
            reject {|lick| discard_any.any? && (discard_any.to_a & lick[:tags]).any?}.
            reject {|lick| discard_all.any? && (discard_all.subset?(Set.new(lick[:tags])))}.
            select {|lick| lick[:holes].length <= ( $opts[:max_holes] || 1000 )}.
            select {|lick| lick[:holes].length >= ( $opts[:min_holes] || 0 )}
  err("None of the #{all_licks.length} licks from #{lfile} has been selected when applying options '--tags-any', '--tags-all', '--no-tags-any', '--no-tags-all', '--max-holes' and '--min-holes'") if licks.length == 0

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
    puts "\n\e[32mGO AHEAD\e[0m\n\n"
    puts 'Now you may try again with three predefined licks'
    puts "from 'Wade in the Water', 'St. Louis Blues' and"
    puts "'Going down that road feeling bad' !"
    puts "(all in my own, rather imperfect recording)"
    puts "If you like this mode and want to make it more useful,"
    puts "then consider adding more licks to:"
    puts "#{lfile}"
    puts "(where you may also reread these suggestions)"
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

