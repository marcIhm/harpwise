
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

function hwh {
    command=$(cat $(ls ~/.harpwise/invocations/* | grep -v README) | awk '{print $(NF-1), $NF, $0}' | sort | cut -f4- -d' ' | fzf -e --query "${*:-}" --no-sort --tac --prompt "${HARPWISE_COMMAND:-harpwise} " --print-query | tail -1 | sed 's/ *#.*//')
    read -e -i "${HARPWISE_COMMAND:-harpwise} $command" edited
    history -s $edited
    eval $edited
}
