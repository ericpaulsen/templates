terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 0.6.21"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.18"
    }
  }
}

data "coder_workspace" "me" {}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

resource "coder_agent" "coder" {
  os             = "linux"
  arch           = "amd64"
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

data "coder_parameter" "devcontainer" {
  name    = "Devcontainer repo"
  type    = "string"
  mutable = true
  icon    = "https://git-scm.com/images/logos/downloads/Git-Icon-1788C.png"
}

resource "kubernetes_persistent_volume_claim" "workspaces" {
  metadata {
    name = "coder-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}"
  }
  wait_until_bound = false
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "2Gi"
      }
    }
  }
}

resource "kubernetes_pod" "main" {
  count = data.coder_workspace.me.start_count
  metadata {
    name = "coder-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}"
  }
  spec {
    automount_service_account_token = false
    container {
      name              = "dev"
      image             = "kylecarbs/envbuilder:latest"
      image_pull_policy = "Always"
      security_context {
        run_as_user = "0"
      }
      env {
        name  = "CODER_AGENT_TOKEN"
        value = coder_agent.coder.token
      }
      env {
        name  = "CODER_AGENT_URL"
        value = data.coder_workspace.me.access_url
      }
      env {
        name  = "GIT_URL"
        value = data.coder_parameter.devcontainer.value
      }
      env {
        name  = "INSECURE"
        value = "true"
      }
      env {
        name  = "INIT_SCRIPT"
        value = coder_agent.coder.init_script
      }
      volume_mount {
        mount_path = "/workspaces"
        name       = "workspaces"
        read_only  = false
      }
    }

    volume {
      name = "workspaces"
      persistent_volume_claim {
        claim_name = kubernetes_persistent_volume_claim.workspaces.metadata.0.name
        read_only  = false
      }
    }
  }
}

