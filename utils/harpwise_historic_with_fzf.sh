
#
#  Source this script for a bash-function hwh ("hwh" stands for harpwise historic) to invoke
#  fzf ("fuzzy finder") on the invocation-files of harpwise. fzf needs to be installed as a
#  prerequisite.
#
#  The variable HARPWISE_COMMAND can be used to specify a command to invoke harpwise; the
#  default is 'harpwise' but can be changed to something different, e.g. an alias,
#  e.g. 'hw', if you prefer.
#
#  Then invoke e.g. 'hwh' or 'hwh play' and continue completion by typing; finish with
#  RETURN. The last match will be your new commandline and can be edited further; tyüe
#  RETURN again to execute it
#

# Note for development: This needs to run under bash as well as zsh; so only the common
# subset of features is available

function hwh {
    
    cmd=$( # read every file but the README
	cat $(ls ~/.harpwise/invocations/* | grep -v README) | 
	    # puts date and time from lines first for sorting
	    awk '{print $(NF-1), $NF, $0}' |
	    # sort according to date and time
	    sort |
	    # remove date, time and program-name from front, but keep all the rest
	    # (including time/date-comment)
	    cut -f4- -d' ' |
	    # feed it to fzf; no need to sort; reverse order
	    fzf -e --query "${*:-}" --no-sort --tac --prompt "${HARPWISE_COMMAND:-harpwise} " |
	    # remove time/date-comment
	    sed 's/ *#.*//'
       )

    if [ -z "$cmd" ]; then
	echo "canceled"
    else
	fullcmd="${HARPWISE_COMMAND:-harpwise} ${cmd}"
	history -s $fullcmd
	eval $fullcmd
    fi
}
