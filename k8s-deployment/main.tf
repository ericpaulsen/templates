terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 0.9.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.18"
    }
  }
}

data "coder_workspace" "me" {}

provider "kubernetes" {
  # this is blank because the Coder control plane is running in the same namespace
  # where the pod will be deployed
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

resource "kubernetes_deployment" "hello_world" {
  count            = data.coder_workspace.me.start_count
  wait_for_rollout = false
  metadata {
    name      = "coder-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}"
    namespace = "eric-oss"
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        # my username and workspace name
        app = "${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}"
      }
    }

    template {
      metadata {
        labels = {
          app                  = "${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}"
          "eric.coder.example" = "true"
        }
      }

      spec {
        container {
          image   = "codercom/enterprise-base:ubuntu"
          name    = "dev"
          command = ["sh", "-c", coder_agent.coder.init_script]

          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.coder.token
          }
          volume_mount {
            mount_path = "/home/coder"
            name       = "home-directory"
          }
        }
        volume {
          name = "home-directory"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.home-directory.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "home-directory" {
  metadata {
    name      = "home-coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}"
    namespace = "eric-oss"
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "20Gi"
      }
    }
  }
}
