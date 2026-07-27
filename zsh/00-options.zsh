setopt HIST_IGNORE_SPACE

USERNAME=$USER

LINUX=false
MACOS=false
case "$(uname)" in
  Linux)  LINUX=true ;;
  Darwin) MACOS=true ;;
esac

ITERM=false
if [[ ${TERM_PROGRAM} =~ .*iTerm* ]]; then
  ITERM=true
fi

VSCODE=false
if [[ ${TERM_PROGRAM} =~ .*vscode* ]]; then
  VSCODE=true
fi

WSL=false
if [ "${WSL_DISTRO_NAME}x" != "x" ]; then
  if [ "${WSL_USER}x" != "x" ]; then
    USERNAME=$WSL_USER
  fi
  WSL=true
fi

USEPOWER9k=false

if [[ "${ITERM}" = true || "${LINUX}" = true || "${MACOS}" = true ]]; then
  USEPOWER9k=true

  if [ "${WSL}" = true ]; then
    USEPOWER9k=true
  fi

  if [ "${VSCODE}" = true ]; then
    USEPOWER9k=false
  fi
fi

export EDITOR=nano
