#
# Handling of licks
#


$lick_file_mod_time = nil
$lick_file = nil

def read_licks

  $lick_file = lfile = get_lick_file
  $lick_file_mod_time = File.mtime($lick_file)

  word_re ='[[:alnum:]][-_:/\.[:alnum:]]*'
  all_keys = %w(holes notes rec rec.start rec.length tags tags.add)

  all_licks = []
  derived = []
  all_lick_names = Set.new
  include = Hash.new
  vars = Hash.new
  lick = name = nil

  (File.readlines(lfile) << '[include]').each do |line|  # trigger checks for new lick even at end of file
    line.chomp!
    line.gsub!(/#.*/,'')
    line.strip!
    next if line == ''
    derived << line

    # [section]
    if md = line.match(/^\[(#{word_re})\]$/)
      derived.insert(-2,'')
      nname = md[1]

      # Do final processing of previous lick: merging with include and replacement of vars
      if lick
        if name == 'include'
          include = lick
        elsif name == 'vars'
          # vars have already been assigned; nothing to do here
        else
          err "Lick [#{name}] does not contain any holes" unless lick[:holes]  
          lick[:tags] = ([lick[:tags] || include[:tags]] + [lick[:tags_add]]).flatten.select(&:itself)
          lick[:desc] = [name, lick[:tags]].flatten.join(',')
          all_licks << lick
        end
      end
      name = nname

      # start with new lick
      unless %w(include vars).include?(nname)
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
    elsif md = line.match(/^ *(tags.add) *= *(.*?) *$/) ||
         md = line.match(/^ *(tags) *= *(.*?) *$/)
      var, tags = md[1 .. 2]
      var = var.gsub('.','_').to_sym
      err "Section [include] does only allow 'tags', but not 'tags.add'" if name == 'include' && var == :tags_add
      tags.split.each do |tag|
        err "Tags must consist of word characters; '#{tag}' does not" unless tag.match?(/^#{word_re}$/) || tag.match?(/^\$#{word_re}$/) 
      end
      lick[var] = tags.split.map! do |tag|
        if tag.start_with?('$')
          err("Unknown variable #{tag} used in lick #{name}") unless vars[tag]
          vars[tag]
        else
          tag
        end
      end

    # holes = value1 value2 ...
    elsif md = line.match(/^ *holes *= *(.*?) *$/)
      holes = md[1]
      err "File #{lfile} should only contain key 'notes', not 'holes' (below [#{name}])" if lfile['notes']
      lick[:holes] = holes.split.map do |hole|
        err("Hole #{hole} from #{lfile} is not among holes of harp #{$harp_holes}") unless musical_event?(hole) || $harp_holes.include?(hole)
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
        err("Note #{note} from #{lfile} is not among notes of harp #{$harp_notes}") unless musical_event?(note) || $harp_notes.include?(note)
        $note2hole[note]
      end
      derived[-1] = "  holes = " + lick['holes'].join(' ')

    # key = value  (for remaining keys, e.g. rec)
    elsif md = line.match(/^ *(#{word_re}) *= *(#{word_re})$/)
      key, value = md[1..2]
      lick = Hash.new unless lick

      if name == 'include'
        # correct assignment has been handled before
        err "Include section only allows key 'tags', not '#{key}'" 
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
    puts "All Tags from #{lfile}:"
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
    exit
  end

  if $opts[:tags] == 'dump'
    pp all_licks
    exit
  end
  
  err("No licks can be found, because options '--tags' and '--no-tags' have this intersection: #{keep.intersection(discard).to_a}") if keep.intersection(discard).any?

  err("There are some tags in option '--tags' and '--no-tags' #{tags_in_opts.to_a} which are not in lick file #{lfile} #{tags_in_licks.to_a}; unknown in '--tags' and '--no-tags' are: #{(tags_in_opts - tags_in_licks).to_a}") unless tags_in_opts.subset?(tags_in_licks)

  licks = all_licks.
            select {|lick| keep.empty? || (keep.to_a & lick[:tags]).any?}.
            reject {|lick| discard.any? && (discard.to_a & lick[:tags]).any?}.
            select {|lick| lick[:holes].length <= ( $opts[:max_holes] || 1000 )}.
            uniq {|lick| lick[:holes]}

  err("None of the #{all_licks.length} licks from #{lfile} has been selected when applying options '--tags' and '--no-tags' and '--max-holes'") if licks.length == 0

  licks
end


def create_initial_lick_file lfile
  puts "\nLick file\n\n  #{lfile}\n\ndoes not exist !"
  puts "\nCreating it with a single sample lick (and comments);"
  puts "however, you need to add more licks yourself,"
  puts "to make this mode (memorize) really useful."
  puts
  File.open(lfile, 'w') do |f|
    f.write <<~end_of_content
        #
        # Library of licks used in modes memorize or play.
        #
        #
        # This file is made up of [sections].
        # Empty lines and comments are ignored.
        #
        # Special sections are:
        #   [vars]     defining global variables to be used in tags;
        #              may help to save some typing
        #   [include]  define values, that will be included in any lick
        #              currently works only for tags; in an individual
        #              lick you may override or add to this.
        # both sections are optional.
        #
        # Normal sections each define one lick by starting 
        # with its [name].
        #
        # A lick requires a series of holes ('holes =') to be played,
        # but may also contain special accustic events (e.g. '(pull)') 
        # that are recognized by the surrounding parens and will 
        # not be played; they just serve as a kind of reminder.
        #
        # A lick may contain a recording ('rec ='), that can be played
        # on request; it will be searched in subdir 'recordings'
        # and needs to be in the key of 'c', which will be
        # transposed as required. You may also specify 'rec.start =' and
        # 'rec.duration ='
        #
        # It is recommended to assign tags to a lick, that can later be used
        # to select licks on the commandline with options '--tags' and
        # '--no-tags'. To this end, licks may contain: 
        #
        #  'tags.add =' to add to the licks from the last [include], or 
        #  'tags ='     to specify the list of tags disregarding any 
        #               includes
        #
        # Initially this file is populated with sample licks for a
        # richter harp; they may not work for other harps however.
        #
        # You will need to add licks and recordings, before
        # the feature memorize can be useful.
        #
        # To this end you may search the web; make sure, to grep 
        # audio samples too or record them yourself.
        #
        # A great one-stop source of licks complete with audio samples 
        # is the book:
        #
        #    100 Authentic Blues Harmonica Licks
        #
        # by Steve Cohen
        #

        [include]
          # this applies for all licks until overwritten by another [include];
          # tags specified in the individual lick will be added
          tags = samples

        [juke]
          holes = -1 -2/ -3// -3 -4 -4
          # we also have a recording for this lick
          rec = juke.mp3
          # next two are optional
          rec.start = 2.2
          rec.length = 4
          # This lick will have the tags 'samples' and 'favorites'
          tags.add = favorites  
        
        [special]
          holes = -1 +1 -2+3 (pull) -1
          # unfortunately no recording ...

        [vars]
          # may help to save typing 
          $source = theory

        [include]
          # section [include] may appear multiple times
          tags = scales $source

        [blues]
          holes = +1 -1/ -1 -2// -2+3 -3/ +4 -4/ -4 -5 +6 -6/ -6 +7 -8 -9 +9 -10
          # has tags 'scales' and 'theory'
        
        [mape] # major pentatonic
          holes = -1 +2 -2+3 -3// -3 -4 +5 +6 -6 -7 -8 +8 +9
          # has tags 'scales' only
          tags = scales

        end_of_content

    if $opts[:testing]
      f.write <<~end_of_content

        [include]
          tags = testing

        [one]
          holes = +1 +1 -1

        [two] 
          holes = +1 +1 -1 +1
          
        [three]
          holes = +1 +1 -1

        end_of_content
    end
  end
  FileUtils.cp('recordings/juke.mp3', $lick_dir + '/recordings') 
  exit
  puts "Now you may try again with a few predefined licks (e.g. 'ending') ..."
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
    $licks = read_licks
    true
  else
    false
  end
end


def musical_event? hole_or_note
  hole_or_note.match?(/^\(\S*\)$/)
end
