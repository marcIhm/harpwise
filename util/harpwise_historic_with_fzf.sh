
# Source this script for a bash-function (hwh stands for harpwise
# historic) to invoke fzf on the automatic invocation-files of
# harpwise. fzf needs to be installed as a prerequisite.

# The variable HARPWISE_COMMAND can be used to specify a command to
# invoke harpwise; the default is 'harpwise' but can be changed to
# something different, e.g. an alias, e.g. 'hw', if you prefer.

# Then invoke e.g. 'hwh' or 'hwh play' and continue completion by
# typing; sult will be on the commandline and can be edited further.

function hwh {
    command=$(cat ~/.harpwise/invocations/* | cut -d" " -f2- | fzf --query "${@:-}" --prompt "${HARPWISE_COMMAND:-harpwise} " --print-query | tail -1)
    read -e -i "${HARPWISE_COMMAND:-harpwise} $command" edited
    history -s $edited
    eval $edited
}
