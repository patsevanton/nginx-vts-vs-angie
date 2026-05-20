data "yandex_client_config" "client" {}

locals {
  yc_folder_id = var.yc_folder_id != "" ? var.yc_folder_id : data.yandex_client_config.client.folder_id
}
