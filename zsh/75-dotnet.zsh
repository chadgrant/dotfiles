# zsh parameter completion for the dotnet CLI
_dotnet_zsh_complete()
{
  local completions=("$(dotnet complete "$words")")

  if [ -z "$completions" ]
  then
    _arguments '*::arguments: _normal'
    return
  fi

  _values = "${(ps:\n:)completions}"
}

# compdef exists only once compinit has run, which prezto does; a shell
# without prezto (a container's fresh home) has no completion system to join.
if (( $+functions[compdef] )); then
  compdef _dotnet_zsh_complete dotnet
fi
