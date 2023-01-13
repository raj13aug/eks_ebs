
data "aws_eks_cluster" "eks" {
  name = "i2"
}


data "aws_arn" "oidc_provider_arn" {
  arn = "i2"
}

###################
# EBS CSI Role    #
###################

module "ebs_csi_eks_role" {
  source    = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  role_name = "ebs_csi"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = data.aws_arn.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}


###################
# EBS CSI Driver  #
###################

resource "helm_release" "ebs_csi_driver" {
  name       = "aws-ebs-csi-driver"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
  chart      = "aws-ebs-csi-driver"

  set {
    name  = "controller.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    type  = "string"
    value = module.ebs_csi_eks_role.iam_role_arn
  }
}


###################
# Storage Classes #
###################

resource "kubernetes_storage_class" "storageclass_gp2" {
  depends_on = [helm_release.ebs_csi_driver, module.ebs_csi_eks_role]
  metadata {
    name = "gp2-encrypted"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  allow_volume_expansion = "true"

  parameters = {
    type      = "gp2"
    encrypted = "true"
  }

}

##########################
# PersistentVolumeClaim  #
##########################

resource "kubernetes_persistent_volume_claim_v1" "efs_pvc" {
  metadata {
    name = "ebs-claim-01"
  }
  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = kubernetes_storage_class.storageclass_gp2.metadata[0].name
    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
  depends_on = [
    kubernetes_storage_class.storageclass_gp2
  ]
}