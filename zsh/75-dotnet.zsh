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

compdef _dotnet_zsh_complete dotnet 2>/dev/null
