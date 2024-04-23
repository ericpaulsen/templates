terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

provider "docker" {
  host = "unix:///run/podman.sock"
}

provider "coder" {}

data "coder_workspace" "me" {}

data "coder_parameter" "os" {
  name         = "os"
  display_name = "Operating system"
  description  = "The operating system to use for your workspace."
  default      = "ubuntu"
  option {
    name  = "Ubuntu"
    value = "ubuntu"
    icon  = "/icon/ubuntu.svg"
  }
  option {
    name  = "Fedora"
    value = "fedora"
    icon  = "/icon/fedora.svg"
  }
}

data "coder_parameter" "repo" {
  name    = "repo"
  type    = "string"
  default = "eric/react-demo.git"
  icon    = "https://git-scm.com/images/logos/downloads/Git-Icon-1788C.png"
}

resource "coder_agent" "dev" {
  arch           = "amd64"
  os             = "linux"
  startup_script = <<EOT
    #!/bin/bash

    # Run once to avoid unnecessary warning: "/" is not a shared mount
    podman ps

    # clone repo
    mkdir -p ~/.ssh
    ssh-keyscan -t ed25519 github.com >> ~/.ssh/known_hosts
    git clone ${data.coder_parameter.repo.value}

    # install code-server
    curl -fsSL https://code-server.dev/install.sh | sh
    code-server --auth none --port 13337 &

  EOT
}

resource "coder_app" "code-server" {
  agent_id     = coder_agent.dev.id
  slug         = "code-server"
  display_name = "VS Code"
  url          = "http://localhost:13337/?folder=/home/coder"
  icon         = "/icon/code.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 5
    threshold = 15
  }
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = "ghcr.io/coder/podman:${data.coder_parameter.os.value}"
  # Uses lower() to avoid Docker restriction on container names.
  name     = "coder-${data.coder_workspace.me.owner}-${lower(data.coder_workspace.me.name)}"
  hostname = lower(data.coder_workspace.me.name)
  dns      = ["1.1.1.1"]

  # Use the docker gateway if the access URL is 127.0.0.1
  #entrypoint = ["sh", "-c", replace(coder_agent.dev.init_script, "127.0.0.1", "host.docker.internal")]

  # Use the docker gateway if the access URL is 127.0.0.1
  command       = ["/bin/bash", "-c", coder_agent.dev.init_script]
  env           = ["CODER_AGENT_TOKEN=${coder_agent.dev.token}"]
  security_opts = ["seccomp=unconfined"]
  privileged    = true

  volumes {
    volume_name    = docker_volume.coder_volume.name
    container_path = "/home/coder/"
    read_only      = false
  }

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
}

resource "docker_volume" "coder_volume" {
  name = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}"
}

resource "docker_volume" "sysbox" {
  name = "sysbox"
}
