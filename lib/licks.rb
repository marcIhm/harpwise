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
          lick[:tags] = replace_vars(vars,([lick[:tags] || default[:tags]] + [lick[:tags_add] || default[:tags_add]]).flatten.select(&:itself),name).sort.uniq
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
      err "Key '#{var}' (below [#{name}]) has already been defined" if lick[var]
      lick[var] = tags.split
      lick[var].each do |tag|
        err "Tags must consist of word characters; '#{tag}' (below [#{name}]) does not" unless tag.match?(/^#{word_re}$/) || tag.match?(/^\$#{word_re}$/) 
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
      err "Lick #{name} does not contain any holes (#{lfile})" unless lick[:holes].length > 0
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
      var = var.gsub('.','_').to_sym
      err "Key '#{var}' (below [#{name}]) has already been defined" if lick[var]
      lick[var] = desc
      
    # key = value  (for remaining keys, e.g. rec)
    elsif md = line.match(/^ *(#{word_re}) *= *(#{word_re})$/)
      key, value = md[1..2]

      if name == 'default'
        # correct assignment has been handled before
        err "Default section only allows keys tags, tags.add, desc or desc.add ; not '#{key}'" 
      elsif name == 'vars'
        # correct assignments have been handled before
        err "Section [vars] may only contain variables (starting with '$'), not #{key} (#{lfile})"
      # normal lick
      else
        # tags, holes and notes have already been handled above special
        if all_keys.include?(key)
          skey = key.gsub('.','_').to_sym
          err "Key '#{skey}' (below [#{name}]) has already been defined" if lick[skey]
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

  # keep only those licks, that match any of the four --tags arguments
  keep_any = Set.new($opts[:tags_any]&.split(','))
  keep_all = Set.new($opts[:tags_all]&.split(','))
  discard_any = Set.new($opts[:no_tags_any]&.split(','))
  discard_all = Set.new($opts[:no_tags_all]&.split(','))
  tags_in_opts = Set.new(discard_any + discard_all + keep_any + keep_all)
  tags_in_licks = Set.new(all_licks.map {|l| l[:tags]}.flatten)

  all_tag_opts = [$opts[:tags_any], $opts[:tags_all], $opts[:no_tags_any], $opts[:no_tags_all]]

  if (keep_all).intersection(discard_any).any?
    if graceful
      return [[],[]]
    else
      err "No licks can be found, because options '--tags-all' and '--no-tags-any' have this intersection: #{(keep_all).intersection(discard_any).to_a}"
    end
  end
    
  if !tags_in_opts.subset?(tags_in_licks)
    if graceful
      return [[],[]]
    else
      err "There are some tags in option '--tags-any', '--tags-all', '--no-tags-any' or '--no-tags-all' #{tags_in_opts.to_a} which are not in lick file #{lfile} #{tags_in_licks.to_a}; unknown in options are: #{(tags_in_opts - tags_in_licks).to_a}"
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
          tags.add = x
          desc = a
          desc.add = b

        [one]
          holes = +1 +1 -1

        [two] 
          holes = +1 +1 -1 +1
          tags = y
          tags.add =
          desc = c
          
        [three]
          holes = +1 +1 -1
          tags.add = z
          desc.add = d

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

