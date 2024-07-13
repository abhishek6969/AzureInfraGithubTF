variable "worker_groups" {
  description = "List of worker groups"
  type = map(object({
    name = string
    os   = string
  }))
  default = {
    linux_workers = {
      name = "lirook-linux-workers"
      os   = "Linux"
    }
    windows_workers = {
      name = "lirook-windows-workers"
      os   = "Windows"
    }
  }
}
variable "csv_file" {
  description = "Path to the CSV file containing parameters"
  default     = "parameters.csv"
}

locals {
  csv_data = csvdecode(file(var.csv_file))
  workspace_name = local.csv_data[0].workspace_name
  automation_account_name = local.csv_data[0].automation_account_name
  metric_dcr_name = local.csv_data[0].metric_dcr_name
  RG_name = local.csv_data[0].RG_Name
  RG_location = local.csv_data[0].RG_location

}