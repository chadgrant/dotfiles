export DOCKER_DEFAULT_PLATFORM=linux/amd64

function docker_stop_containers() {
  docker_start
  if [[ $(docker ps -q) ]]; then
    echo "[docker]: stopping containers ..."
    docker stop $(docker ps -q)
  fi
}

function docker_remove_containers() {
  docker_start
  if [[ $(docker ps -qf status=exited) ]]; then
    echo "[docker]: removing containers ..."
    docker rm $(docker ps -qf status=exited)
  fi
  if [[ $(docker ps -qf status=created) ]]; then
    echo "[docker]: removing containers ..."
    docker rm $(docker ps -qf status=created)
  fi
}

function docker_remove_dangling_images() {
  docker_start
  if [[ $(docker images -qf dangling=true) ]]; then
    echo "[docker]: removing dangling images ..."
    docker rmi $(docker images -qf dangling=true)
  fi
}

function docker_remove_dangling_volumes() {
  docker_start
  if [[ $(docker volume ls -qf dangling=true) ]]; then
    echo "[docker]: removing dangling volumes ..."
    docker volume rm $(docker volume ls -qf dangling=true)
  fi
}

function docker_remove_dangling_networks() {
  docker_start
  if [[ $(docker network ls -qf dangling=true) ]]; then
    echo "[docker]: removing dangling networks ..."
    docker network rm $(docker network ls -qf dangling=true)
  fi
}

function docker_remove_images() {
  docker_start
  if [[ $(docker images --format '{{.Repository}}:{{.Tag}}' | grep "$1") ]]; then
    docker rmi -f $(docker images --format '{{.Repository}}:{{.Tag}}' | grep "$1")
  fi
}

function docker_clean() {
  docker_start
  docker_stop_containers
  docker_remove_containers
  docker_remove_dangling_images
  docker_remove_dangling_volumes
  docker_remove_dangling_networks
}

function docker_images() {
  docker_start
  docker images
}

function docker_start() {
  if [ $(uname) = "Linux" ] ; then return 0; fi

  if [ "${WSL_DISTRO_NAME}x" = "x" ]; then
    setopt +o nomatch
    running=$(ps -ax | grep [c]om.docker.hyperkit)
    running="${running#"${running%%[![:space:]]*}"}"
    if [[ ${#running} == 0 ]]; then
      echo "starting docker..."
      open /Applications/Docker.app && sleep 20
    fi
    setopt nomatch
  fi
}

unalias drm drmi drmu drmv drmn ds dc di vpn compose 2>/dev/null
alias drm='docker_remove_containers'
alias drmi='docker_remove_images'
alias drmu='docker_remove_dangling_images'
alias drmv='docker_remove_dangling_volumes'
alias drmn='docker_remove_dangling_networks'
alias ds='docker_stop_containers'
alias dc='docker_clean'
alias di='docker_images'
alias d='docker'
alias k='kubectl'

function compose() {
  docker_start
  docker-compose
}
