terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 0.6.2"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.16.0"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

data "coder_workspace" "me" {}

resource "coder_agent" "main" {
  os             = "linux"
  arch           = "amd64"
  dir            = "/home/coder"
  startup_script = <<EOF
    #!/bin/sh

    # Start Docker
    sudo dockerd &
    curl -fsSL https://code-server.dev/install.sh
    code-server --auth none --port 13337 &
  EOF
}

# code-server
resource "coder_app" "code-server" {
  agent_id = coder_agent.main.id
  slug     = "code-server"
  icon     = "/icon/code.svg"
  url      = "http://localhost:13337?folder=/home/coder"
}

resource "kubernetes_pod" "dev" {
  count = data.coder_workspace.me.start_count
  metadata {
    name      = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}"
    namespace = "eric-oss"
    annotations = {
      "io.kubernetes.cri-o.userns-mode" = "auto:size=65536"
    }
  }

  spec {
    # Use the Sysbox container runtime (required)
    runtime_class_name = "sysbox-runc"
    security_context {
      run_as_user = 1000
      fs_group    = 1000
    }
    toleration {
      effect   = "NoSchedule"
      key      = "sysbox"
      operator = "Equal"
      value    = "oss"
    }
    node_selector = {
      "sysbox-install" = "yes"
    }
    container {
      name = "dev"
      env {
        name  = "CODER_AGENT_TOKEN"
        value = coder_agent.main.token
      }
      image   = "codercom/enterprise-base:ubuntu"
      command = ["sh", "-c", coder_agent.main.init_script]
    }
  }
}
