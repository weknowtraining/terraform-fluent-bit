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

data "aws_iam_policy_document" "assume-role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${replace(var.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.namespace}:fluent-bit"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "fluent-bit-cloudwatch"
  assume_role_policy = data.aws_iam_policy_document.assume-role.json
}

resource "aws_iam_role_policy" "this" {
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.this.json
}

resource "kubernetes_config_map" "cluster-info" {
  metadata {
    name      = "fluent-bit-cluster-info"
    namespace = var.namespace
  }

  data = {
    "CLUSTER_NAME"   = var.cluster_id,
    "HTTP_SERVER"    = var.http_server ? "On" : "Off",
    "HTTP_PORT"      = var.http_server_port,
    "AWS_REGION"     = var.region,
    "READ_FROM_HEAD" = "Off",
    "READ_FROM_TAIL" = "On",
    "LOG_LEVEL"      = var.log_level
  }
}

resource "kubernetes_service_account" "this" {
  metadata {
    name      = "fluent-bit"
    namespace = var.namespace

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.this.arn
    }
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
      "app.kubernetes.io/name" = "fluent-bit"
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

resource "kubernetes_daemonset" "this" {
  metadata {
    name      = "fluent-bit"
    namespace = var.namespace

    labels = {
      "app.kubernetes.io/name"        = "fluent-bit"
      "version"                       = "v1"
      "kubernetes.io/cluster-service" = "true"
    }
  }

  spec {
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "fluent-bit"
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"        = "fluent-bit"
          "version"                       = "v1"
          "kubernetes.io/cluster-service" = "true"
        }
      }

      spec {
        container {
          name  = "fluent-bit"
          image = var.image

          port {
            container_port = var.http_server_port
            name           = "api"
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map.cluster-info.metadata.0.name
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
            limits = {
              memory = "200Mi"
            }

            requests = {
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

        node_selector = var.node_selector

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

        service_account_name            = kubernetes_service_account.this.metadata.0.name
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
