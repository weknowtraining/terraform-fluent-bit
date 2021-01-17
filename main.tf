data "aws_iam_policy_document" "this" {
  statement {
    effect = "Allow"

    actions = [
      "logs:DescribeLogGroups",
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
      "logs:CreateLogGroup"
    ]

    resources = ["*"]
  }
}

# FIXME: Get the OIDC stuff working
resource "aws_iam_user" "this" {
  name = "fluent-bit"
}

resource "aws_iam_access_key" "this" {
  user = aws_iam_user.this.name
}

resource "aws_iam_user_policy" "this" {
  name   = "cloudwatch"
  user   = aws_iam_user.this.id
  policy = data.aws_iam_policy_document.this.json
}

resource "kubernetes_config_map" "cluster-info" {
  metadata {
    name      = "fluent-bit-cluster-info"
    namespace = var.namespace
  }

  data = {
    "cluster.name" = var.cluster_id,
    "http.server"  = "Off",
    "http.port"    = "",
    "logs.region"  = var.region,
    "read.head"    = "Off",
    "read.tail"    = "On"
  }
}

resource "kubernetes_service_account" "this" {
  metadata {
    name      = "fluent-bit"
    namespace = var.namespace
  }

  automount_service_account_token = true
}

resource "kubernetes_cluster_role" "this" {
  metadata {
    name = "fluent-bit-role"
  }

  rule {
    non_resource_urls = ["/metrics"]
    verbs             = ["get"]
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces", "pods", "pods/logs"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "fluent-bit" {
  metadata {
    name = "fluent-bit-role-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "fluent-bit-role"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "fluent-bit"
    namespace = "aws"
  }
}

resource "kubernetes_config_map" "this" {
  metadata {
    name      = "fluent-bit-config"
    namespace = var.namespace
    labels = {
      "k8s-app" = "fluent-bit"
    }
  }

  data = {
    "application-log.conf" = file("${path.module}/application-log.conf")
    "fluent-bit.conf"      = file("${path.module}/fluent-bit.conf")
    "dataplane-log.conf"   = file("${path.module}/dataplane-log.conf")
    "host-log.conf"        = file("${path.module}/host-log.conf")
    "parsers.conf"         = file("${path.module}/parsers.conf")
  }
}

resource "kubernetes_secret" "this" {
  metadata {
    name      = "fluent-bit-aws-credentials"
    namespace = var.namespace

    labels = {
      "k8s-app" = "fluent-bit"
    }
  }

  data = {
    "AWS_ACCESS_KEY_ID"     = aws_iam_access_key.this.id
    "AWS_SECRET_ACCESS_KEY" = aws_iam_access_key.this.secret
  }
}

resource "kubernetes_daemonset" "this" {
  metadata {
    name      = "fluent-bit"
    namespace = var.namespace

    labels = {
      "k8s-app"                       = "fluent-bit"
      "version"                       = "v1"
      "kubernetes.io/cluster-service" = "true"
    }
  }

  spec {
    selector {
      match_labels = {
        "k8s-app" = "fluent-bit"
      }
    }

    template {
      metadata {
        labels = {
          "k8s-app"                       = "fluent-bit"
          "version"                       = "v1"
          "kubernetes.io/cluster-service" = "true"
        }
      }

      spec {
        container {
          name  = "fluent-bit"
          image = var.image

          env_from {
            secret_ref {
              name = "fluent-bit-aws-credentials"
            }
          }

          env {
            name = "AWS_REGION"

            value_from {
              config_map_key_ref {
                name = "fluent-bit-cluster-info"
                key  = "logs.region"
              }
            }
          }

          env {
            name = "CLUSTER_NAME"

            value_from {
              config_map_key_ref {
                name = "fluent-bit-cluster-info"
                key  = "cluster.name"
              }
            }
          }

          env {
            name = "HTTP_SERVER"

            value_from {
              config_map_key_ref {
                name = "fluent-bit-cluster-info"
                key  = "http.server"
              }
            }
          }

          env {
            name = "HTTP_PORT"

            value_from {
              config_map_key_ref {
                name = "fluent-bit-cluster-info"
                key  = "http.port"
              }
            }
          }

          env {
            name = "READ_FROM_HEAD"

            value_from {
              config_map_key_ref {
                name = "fluent-bit-cluster-info"
                key  = "read.head"
              }
            }
          }

          env {
            name = "READ_FROM_TAIL"

            value_from {
              config_map_key_ref {
                name = "fluent-bit-cluster-info"
                key  = "read.tail"
              }
            }
          }

          env {
            name = "HOST_NAME"

            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }

          env {
            name  = "CI_VERSION"
            value = "k8s/1.3.3"
          }

          resources {
            limits {
              memory = "200Mi"
            }

            requests {
              memory = "100Mi"
              cpu    = "500m"
            }
          }

          volume_mount {
            name       = "fluentbitstate"
            mount_path = "/var/fluent-bit/state"
          }

          volume_mount {
            name       = "varlog"
            mount_path = "/var/log"
            read_only  = true
          }

          volume_mount {
            name       = "varlibdockercontainers"
            mount_path = "/var/lib/docker/containers"
            read_only  = true
          }

          volume_mount {
            name       = "fluent-bit-config"
            mount_path = "/fluent-bit/etc/"
          }

          volume_mount {
            name       = "runlogjournal"
            mount_path = "/run/log/journal"
            read_only  = true
          }

          volume_mount {
            name       = "dmesg"
            mount_path = "/var/log/dmesg"
            read_only  = true
          }
        }

        termination_grace_period_seconds = 10

        volume {
          name = "fluentbitstate"

          host_path {
            path = "/var/fluent-bit/state"
          }
        }

        volume {
          name = "varlog"

          host_path {
            path = "/var/log"
          }
        }

        volume {
          name = "varlibdockercontainers"

          host_path {
            path = "/var/lib/docker/containers"
          }
        }

        volume {
          name = "fluent-bit-config"

          config_map {
            name = "fluent-bit-config"
          }
        }

        volume {
          name = "runlogjournal"

          host_path {
            path = "/run/log/journal"
          }
        }

        volume {
          name = "dmesg"

          host_path {
            path = "/var/log/dmesg"
          }
        }

        service_account_name            = "fluent-bit"
        automount_service_account_token = true

        toleration {
          key      = "node-role.kubernetes.io/master"
          operator = "Exists"
          effect   = "NoSchedule"
        }

        toleration {
          operator = "Exists"
          effect   = "NoExecute"
        }

        toleration {
          operator = "Exists"
          effect   = "NoSchedule"
        }
      }
    }
  }
}
