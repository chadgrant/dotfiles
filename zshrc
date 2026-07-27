# Entry point. Everything lives in zsh/, sourced in numeric order.
# ~/.extra is sourced last (by 99-extra.zsh) so it can override anything above.

for fragment in "${${(%):-%N}:A:h}"/zsh/*.zsh(N); do
  source "$fragment"
done
unset fragment
