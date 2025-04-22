variable "alert_rule_groups" {
  description = "List of alert rules to create"
  type = map(object({
    name                   = string
    folder_uid             = string
    check_interval_seconds = number
    org_id                 = optional(number, 1)
    rules = list(object({
      name           = string
      query          = string
      summary        = string
      depth_seconds  = number
      pending_period = string
      no_data_state  = optional(string, "OK")
      exec_err_state = optional(string, "KeepLast")
      dashboard_uid  = string
      panel_id       = string
      labels         = optional(map(string), {})
      datasource = object({
        type = string
        uid  = string
      })
      expressions = optional(list(map(string)), [{ type = "reduce" }, { type = "threshold" }])
    }))
  }))
}
