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
