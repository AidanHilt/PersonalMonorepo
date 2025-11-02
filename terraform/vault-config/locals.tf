locals {
  secret_definitions = [
    {
      name      = "prowlarr"
      namespace = "videos"
      mount     = "videos"
      postgres_secret = true
      data  = {
        apiKey = {}
        postgresPassword = {
          postgres_password = true
        }
        postgresUsername = {
          value = "prowlarr"
        }
      }
    },
    {
      name      = "sonarr"
      namespace = "videos"
      mount     = "videos"
      postgres_secret = true
      data  = {
        apiKey = {}
        postgresPassword = {
          postgres_password = true
        }
        postgresUsername = {
          value = "sonarr"
        }
      }
    },
    {
      name      = "radarr"
      namespace = "videos"
      mount     = "videos"
      postgres_secret = true
      data  = {
        apiKey = {}
        postgresPassword = {
          postgres_password = true
        }
        postgresUsername = {
          value = "radarr"
        }
      }
    },
    {
      name      = "jellyseerr"
      namespace = "videos"
      mount     = "videos"
      data  = {
        apiKey = {}
      }
    },
    {
      name      = "jellyfin"
      namespace = "videos"
      mount     = "videos"
      data  = {
        apiKey = {}
        password = {
          postgres_password = true
        }
        username = {
          value = var.jellyfin_username
        }
      }
    },
    {
      name            = "vpn"
      namespace       = "videos"
      mount           = "videos"
      service_account = "transmission"
      data  = {
        VPN_AUTH  = {
          value = var.vpn_auth
        }
        vpnConfig = {
          value = var.vpn_config
        }
      }
    },
    {
      name            = "postgres"
      namespace       = "postgres"
      mount           = "postgres"
      service_account = "postgres-cluster"
      data  = {
        password = {
          postgres_password = true
        }
        username = {
          value = "postgres"
        }
      }
    },
    {
      name            = "video_stack_configuration"
      namespace       = "argocd"
      mount           = "argocd"
      service_account = "argocd-repo-server"
      path            = "video_stack_configuration"
      auth = {
        role_name = "argocd"
        path = ""
      }
      data  = {
        prowlarrApiKey   = {
          key_name = "prowlarr-apiKey"
        }
        sonarrApiKey     = {
          key_name = "sonarr-apiKey"
        }
        radarrApiKey     = {
          key_name = "radarr-apiKey"
        }
        jellyseerrApiKey = {
          key_name = "jellyseerr-apiKey"
        }
        jellyfinPassword = {
          key_name = "jellyfin-password"
        }
        jellyfinUsername = {
          value = var.jellyfin_username
        }
        jellyfinEmail    = {
          value = var.jellyfin_email
        }
      }
    },
  ]

  unique_mounts = toset([
    for key, secret in local.secret_definitions : secret.mount
  ])
}