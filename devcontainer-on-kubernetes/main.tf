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

resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"
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
        value = coder_agent.main.token
      }
      env {
        name  = "CODER_AGENT_URL"
        value = data.coder_workspace.me.access_url
      }
      env {
        name  = "GIT_URL"
        value = "https://github.com/microsoft/vscode-course-sample"
      }
      env {
        name  = "INSECURE"
        value = "true"
      }
      env {
        name  = "INIT_SCRIPT"
        value = coder_agent.main.init_script
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

