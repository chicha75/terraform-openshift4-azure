resource "azurerm_storage_account" "ignition" {
  name                     = "samgnignition${local.cluster_nr}ffrtest"
  resource_group_name      = var.resource_group_name
  location                 = var.azure_region
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = {
    environment = "staging"
  }
}

data "azurerm_storage_account_sas" "ignition" {
  connection_string = azurerm_storage_account.ignition.primary_connection_string
  https_only        = true

  resource_types {
    service   = false
    container = false
    object    = true
  }

  services {
    blob  = true
    queue = false
    table = false
    file  = false
  }

  #https://github.com/hashicorp/terraform-provider-azurerm/issues/1868#issuecomment-697098941
  #start = timestamp()
  #expiry = timeadd(timestamp(), "24h")
  start = "2000-01-01T00:00:00Z"
  expiry = "2099-12-31T23:59:59Z"

  permissions {
    read    = true
    list    = true
    create  = false
    add     = false
    delete  = false
    process = false
    write   = false
    update  = false
    tag     = false
    filter  = false
  }

}

resource "azurerm_storage_container" "ignition" {
  name                  = "ignition"
  storage_account_name  = azurerm_storage_account.ignition.name
  container_access_type = "private"
}

locals {
  installer_workspace     = "${path.root}/installer-files/${terraform.workspace}/"
  installer_terraform     = "${path.root}/terraformed-files/${terraform.workspace}/"
  openshift_installer_url = "${var.openshift_installer_url}/${var.openshift_version}"
  cluster_nr              = join("", split("-", var.cluster_id))
}

resource "null_resource" "download_binaries" {
  provisioner "local-exec" {
    when = create
    interpreter = [ "/bin/bash", "-c" ]
    command = templatefile("${path.module}/scripts/download.sh.tmpl", {
      installer_workspace  = local.installer_workspace
      installer_terraform  = local.installer_terraform
      installer_url        = local.openshift_installer_url
      airgapped_enabled    = var.airgapped["enabled"]
      airgapped_repository = var.airgapped["repository"]
      pull_secret          = var.openshift_pull_secret
      openshift_version    = var.openshift_version
      path_root            = path.root
    })
  }

  provisioner "local-exec" {
    when    = destroy
    command = "rm -rf installer-files/${terraform.workspace}"
  }

}


resource "null_resource" "generate_manifests" {
  triggers = {
    install_config = data.template_file.install_config_yaml.rendered
  }

  depends_on = [
    null_resource.download_binaries,
    local_file.install_config_yaml
  ]

  provisioner "local-exec" {
    interpreter = [ "/bin/bash", "-c" ]
    command = templatefile("${path.module}/scripts/manifests.sh.tmpl", {
      installer_workspace = local.installer_workspace
      installer_terraform = local.installer_terraform
    })
  }

  provisioner "local-exec" {
    when    = destroy
    command = "true"
    /*
    command = templatefile("${path.module}/scripts/destroymanifests.sh.tmpl", {
      installer_terraform = local.installer_terraform
    })
    */
  }

}

# see templates.tf for generation of yaml config files

resource "null_resource" "generate_ignition" {
  depends_on = [
    null_resource.download_binaries,
    local_file.install_config_yaml,
    null_resource.generate_manifests,
    local_file.cluster-infrastructure-02-config,
    local_file.cluster-dns-02-config,
    local_file.cloud-provider-config,
    local_file.openshift-cluster-api_master-machines,
    local_file.openshift-cluster-api_worker-machineset,
    local_file.openshift-cluster-api_infra-machineset,
    local_file.cluster-ingress-default-ingresscontroller,
    local_file.openshift-cluster-worker-machines,
    local_file.cluster-network-02-config,
    local_file.configure-image-registry-job-serviceaccount,
    local_file.configure-image-registry-job-clusterrole,
    local_file.configure-image-registry-job-clusterrolebinding,
    local_file.configure-image-registry-job,
    local_file.configure-ingress-job-serviceaccount,
    local_file.configure-ingress-job-clusterrole,
    local_file.configure-ingress-job-clusterrolebinding,
    local_file.configure-ingress-job,
    local_file.private-cluster-outbound-service,
    local_file.airgapped_registry_upgrades,
    #local_file.ingresscontroller-default,
    local_file.cloud-creds-secret-kube-system,
    #local_file.cluster-scheduler-02-config,
    local_file.cluster-monitoring-configmap,
    #local_file.private-cluster-outbound-service,
  ]

  provisioner "local-exec" {
    interpreter = [ "/bin/bash", "-c" ]
    command = templatefile("${path.module}/scripts/ignition.sh.tmpl", {
      installer_workspace = local.installer_workspace
      installer_terraform = local.installer_terraform
      cluster_id          = var.cluster_id
    })
  }

  provisioner "local-exec" {
    when    = destroy
    command = "true"
    /*
    command = templatefile("${path.module}/scripts/destroyignition.sh.tmpl", {
      installer_terraform = local.installer_terraform
    })
    */
  }

}

resource "azurerm_storage_blob" "ignition-bootstrap" {
  name                   = "bootstrap.ign"
  source                 = "${local.installer_workspace}/bootstrap.ign"
  storage_account_name   = azurerm_storage_account.ignition.name
  storage_container_name = azurerm_storage_container.ignition.name
  type                   = "Block"
  depends_on = [
    null_resource.generate_ignition
  ]
}

resource "azurerm_storage_blob" "ignition-master" {
  name                   = "master.ign"
  source                 = "${local.installer_workspace}/master.ign"
  storage_account_name   = azurerm_storage_account.ignition.name
  storage_container_name = azurerm_storage_container.ignition.name
  type                   = "Block"
  depends_on = [
    null_resource.generate_ignition
  ]
}

resource "azurerm_storage_blob" "ignition-worker" {
  name                   = "worker.ign"
  source                 = "${local.installer_workspace}/worker.ign"
  storage_account_name   = azurerm_storage_account.ignition.name
  storage_container_name = azurerm_storage_container.ignition.name
  type                   = "Block"
  depends_on = [
    null_resource.generate_ignition
  ]
}

data "ignition_config" "master_redirect" {
  replace {
    source = "${azurerm_storage_blob.ignition-master.url}${data.azurerm_storage_account_sas.ignition.sas}"
    #source = "${azurerm_storage_blob.ignition-master.url}"
  }
}

data "ignition_config" "bootstrap_redirect" {
  replace {
    source = "${azurerm_storage_blob.ignition-bootstrap.url}${data.azurerm_storage_account_sas.ignition.sas}"
    #source = "${azurerm_storage_blob.ignition-bootstrap.url}"
  }
}

data "ignition_config" "worker_redirect" {
  replace {
    source = "${azurerm_storage_blob.ignition-worker.url}${data.azurerm_storage_account_sas.ignition.sas}"
    #source = "${azurerm_storage_blob.ignition-worker.url}"
  }
}
