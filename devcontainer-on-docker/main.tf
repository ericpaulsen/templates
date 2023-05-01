terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 0.7.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.1"
    }
  }
}

data "coder_workspace" "me" {}

provider "docker" {}

resource "coder_agent" "coder" {
  os   = "linux"
  arch = "amd64"
  dir  = "/workspaces/vscode"

  startup_script = <<EOT
#!/bin/bash

# install and start code-server
curl -fsSL https://code-server.dev/install.sh | sh
code-server --auth none --port 13337 >/dev/null 2>&1 &

  EOT
}

# code-server
resource "coder_app" "code-server" {
  agent_id     = coder_agent.coder.id
  slug         = "code-server"
  display_name = "VS Code Browser"
  icon         = "/icon/code.svg"
  url          = "http://localhost:13337?folder=/home/coder"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 3
    threshold = 10
  }
}

resource "docker_volume" "workspaces" {
  name = "coder-${data.coder_workspace.me.id}"
  # Protect the volume from being deleted due to changes in attributes.
  lifecycle {
    ignore_changes = all
  }
}

data "docker_registry_image" "envbuilder" {
  name = "kylecarbs/envbuilder:latest"
}

data "coder_parameter" "devcontainer" {
  name    = "Devcontainer repo"
  type    = "string"
  mutable = true
  icon    = "https://git-scm.com/images/logos/downloads/Git-Icon-1788C.png"
}

resource "docker_image" "envbuilder" {
  name          = data.docker_registry_image.envbuilder.name
  pull_triggers = [data.docker_registry_image.envbuilder.sha256_digest]
}

resource "docker_container" "workspace" {
  count   = data.coder_workspace.me.start_count
  image   = docker_image.envbuilder.name
  runtime = "sysbox-runc"
  # Uses lower() to avoid Docker restriction on container names.
  name = "coder-${data.coder_workspace.me.owner}-${lower(data.coder_workspace.me.name)}"
  # Hostname makes the shell more user friendly: coder@my-workspace:~$
  hostname = data.coder_workspace.me.name
  env = [
    "CODER_AGENT_TOKEN=${coder_agent.coder.token}",
    "CODER_AGENT_URL=${data.coder_workspace.me.access_url}",
    "GIT_URL=${data.coder_parameter.devcontainer.value}",
    "INIT_SCRIPT=${replace(coder_agent.coder.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")}"
  ]
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  volumes {
    container_path = "/workspaces"
    volume_name    = docker_volume.workspaces.name
    read_only      = false
  }
}
