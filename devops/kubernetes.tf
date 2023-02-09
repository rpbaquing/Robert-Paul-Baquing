#### Ingress ####
resource "kubernetes_ingress_v1" "main" {
  metadata {
    name = var.name
    annotations = {
      "networking.gke.io/v1beta1.FrontendConfig" = "${var.name}-frontendconfig"
      "kubernetes.io/ingress.global-static-ip-name" = google_compute_global_address.ingress.name
      "networking.gke.io/managed-certificates" = "${var.name}-certificate"
    }
  }

  spec {
    rule {
      host = var.web_domain
      http {
        path {
          backend {
            service {
              name = kubernetes_service.web.metadata[0].name
              port {
                number = 3000
              }
            }
          }
        }
      }
    }
    rule {
      host = var.api_domain
      http {
        path {
          backend {
            service {
              name = kubernetes_service.api.metadata[0].name
              port {
                number = 3000
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    null_resource.managed_certificate,
    null_resource.frontend_config,
    null_resource.backend_config_web,
    null_resource.backend_config_api,
    kubernetes_service.web,
    kubernetes_service.api
  ]
}

resource "null_resource" "managed_certificate" {
  provisioner "local-exec" {
    command = <<EOT
kubectl apply -f - -- <<EOF
apiVersion: networking.gke.io/v1
kind: ManagedCertificate
metadata:
  name: ${var.name}-certificate
spec:
  domains:
    - ${var.web_domain}
    - ${var.api_domain}
EOF
EOT
  }

  depends_on = [
    google_container_node_pool.main
  ]
}

resource "null_resource" "frontend_config" {
  provisioner "local-exec" {
    command = <<EOT
kubectl apply -f - -- <<EOF
apiVersion: networking.gke.io/v1beta1
kind: FrontendConfig
metadata:
  name: ${var.name}-frontendconfig
spec:
  redirectToHttps:
    enabled: true
    responseCodeName: MOVED_PERMANENTLY_DEFAULT
EOF
EOT
  }

  depends_on = [
    google_container_node_pool.main
  ]
}

resource "null_resource" "backend_config_api" {
  provisioner "local-exec" {
    command = <<EOT
kubectl apply -f - -- <<EOF
apiVersion: cloud.google.com/v1
kind: BackendConfig
metadata:
  name: ${var.name}-api
spec:
  healthCheck:
    requestPath: /api/status
    port: 3000
EOF
EOT
  }

  depends_on = [
    google_container_node_pool.main
  ]
}

resource "null_resource" "backend_config_web" {
  provisioner "local-exec" {
    command = <<EOT
kubectl apply -f - -- <<EOF
apiVersion: cloud.google.com/v1
kind: BackendConfig
metadata:
  name: ${var.name}-web
spec:
  cdn:
    enabled: true
  healthCheck:
    requestPath: /healthcheck
    port: 3000
EOF
EOT
  }

  depends_on = [
    google_container_node_pool.main
  ]
}

#### Web Service ####
resource "kubernetes_deployment" "web" {
  metadata {
    name = "web"
    labels = {
      tier = "web"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        tier = "web"
      }
    }

    template {
      metadata {
        labels = {
          tier = "web"
        }
      }

      spec {
        container {
          image = "${local.artifact_registry_url}/web:latest"
          name  = "web"

          env {
            name  = "API_HOST"
            value = var.api_domain
          }

          env {
            name  = "PORT"
            value = "3000"
          }

          resources {
            limits = {
              cpu    = "350m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "50Mi"
            }
          }
        }
      }
    }
  }
  
  depends_on = [
    google_container_node_pool.main,
    data.google_client_config.provider
  ]
}

resource "kubernetes_service" "web" {
  metadata {
    name = "web"
    annotations = {
      "cloud.google.com/backend-config" = "{\"ports\": {\"web\":\"${var.name}-web\"}}"
      "cloud.google.com/neg" = "{\"ingress\": true}"
    }
  }
  spec {
    selector = {
      tier = "web"
    }
    port {
      name        = "web"
      port        = 3000
      target_port = 3000
    }
    type = "NodePort"
  }

  depends_on = [
    kubernetes_deployment.web
  ]
}

resource "kubernetes_horizontal_pod_autoscaler_v2" "web" {
  metadata {
    name = "web"
  }

  spec {
    min_replicas = 1
    max_replicas = 1

    scale_target_ref {
      kind = "Deployment"
      name = kubernetes_deployment.web.metadata[0].name
    }

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type = "Utilization"
          average_utilization = "75"          
        }
      }
    }
  }
}


#### API Service ####
resource "kubernetes_deployment" "api" {
  metadata {
    name = "api"
    labels = {
      tier = "api"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        tier = "api"
      }
    }

    template {
      metadata {
        labels = {
          tier = "api"
        }
      }

      spec {
        container {
          image = "${local.artifact_registry_url}/api:latest"
          name  = "api"

          env {
            name  = "PORT"
            value = "3000"
          }

          env {
            name  = "DBHOST"
            value = google_sql_database_instance.main.private_ip_address
          }

          env {
            name  = "DBPORT"
            value = "5432"
          }

          env {
            name  = "DB"
            value_from {
              secret_key_ref {
                  name = kubernetes_secret.db_credentials.metadata[0].name
                  key  = "DB"
              }
            }
          }

          env {
            name  = "DBUSER"
            value_from {
              secret_key_ref {
                  name = kubernetes_secret.db_credentials.metadata[0].name
                  key  = "DBUSER"
              }
            }
          }

          env {
            name  = "DBPASS"
            value_from {
              secret_key_ref {
                  name = kubernetes_secret.db_credentials.metadata[0].name
                  key  = "DBPASS"
              }
            }
          }

          resources {
            limits = {
              cpu    = "350m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "50Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/api/status"
              port = 3000
            }
          }

          readiness_probe {
            http_get {
              path = "/api/status"
              port = 3000
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_secret.db_credentials
  ]
}

resource "kubernetes_service" "api" {
  metadata {
    name = "api"
    annotations = {
      "cloud.google.com/backend-config" = "{\"ports\": {\"api\":\"${var.name}-api\"}}"
      "cloud.google.com/neg" = "{\"ingress\": true}"
    }
  }
  spec {
    selector = {
      tier = "api"
    }
    port {
      name        = "api"
      port        = 3000
      target_port = 3000
    }
    type = "NodePort"
  }

  depends_on = [
    kubernetes_deployment.api
  ]
}

resource "kubernetes_horizontal_pod_autoscaler_v2" "api" {
  metadata {
    name = "api"
  }

  spec {
    min_replicas = 1
    max_replicas = 1

    scale_target_ref {
      kind = "Deployment"
      name = kubernetes_deployment.api.metadata[0].name
    }

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type = "Utilization"
          average_utilization = "75"  
        }
      }
    }
  }
}

resource "kubernetes_secret" "db_credentials" {
  metadata {
    name = "db-credentials"
  }

  data = {
    DB     = google_sql_database.main.name
    DBUSER = google_sql_user.main.name
    DBPASS = random_password.database.result
  }
  
  depends_on = [
    google_container_node_pool.main,
    data.google_client_config.provider
  ]
}