### Documents ###

export DOC_ROOT=~/Documents

if [ "${WSL_DISTRO_NAME}x" != "x" ]; then
  if [ -d /c/Users/${USERNAME}/Documents/github ] ; then
    export DOC_ROOT=/c/Users/${USERNAME}/Documents/github
  fi
fi

unalias documents 2>/dev/null
alias documents='cd $DOC_ROOT'

DOC_DIRS=(chadgrant icanotes shipt playstudios spree)
for parent in $DOC_DIRS; do
  [ -d "$DOC_ROOT/$parent" ] || continue
  unalias $parent 2>/dev/null
  alias $parent="cd $DOC_ROOT/$parent"
  for d in $DOC_ROOT/$parent/*(N); do
    [ -d "$d" ] || continue
    dir=$(basename $d)
    unalias $dir 2>/dev/null
    alias $dir="cd $DOC_ROOT/$parent/$dir"
  done
done

unalias goproxy 2>/dev/null
