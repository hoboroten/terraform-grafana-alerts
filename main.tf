locals {
  regex_query = "(^[^<>]*) (<|>) (.+)"
  operator_translation = {
    "<" = "lt"
    ">" = "gt"
  }

  #TODO add custom datasource config
  default_datasource_config = {
    loki = {
      queryType = "range"
    }

  }
}

resource "grafana_rule_group" "provisioned_alerts" {
  for_each           = var.alert_rule_groups #var.alert_rule_groups
  name               = each.value["name"]
  folder_uid         = each.value["folder_uid"]
  interval_seconds   = each.value["check_interval_seconds"]
  org_id             = each.value["org_id"]
  disable_provenance = true
  dynamic "rule" {
    for_each = each.value["rules"]
    content {
      name           = rule.value["name"]
      for            = rule.value["pending_period"]
      condition      = "ALERTCONDITION"
      no_data_state  = rule.value["no_data_state"]
      exec_err_state = rule.value["exec_err_state"]
      annotations = {
        "__dashboardUid__" = rule.value["dashboard_uid"]
        "__panelId__"      = rule.value["panel_id"]
        "dashboardurl"     = "{{ externalURL }}d/${rule.value["dashboard_uid"]}"
        "panelurl"         = "{{ externalURL }}d/${rule.value["dashboard_uid"]}?viewPanel=${rule.value["panel_id"]}" #TODO добавить возможность вставлять фильтры по динамическим лейблам из алертов
        "summary"          = rule.value["summary"]
      }
      labels    = rule.value["labels"]
      is_paused = false

      dynamic "data" {
        for_each = [rule.value]
        content {
          ref_id     = "QUERY"
          query_type = "range"
          relative_time_range {
            from = data.value["depth_seconds"]
            to   = 0
          }
          datasource_uid = data.value.datasource.uid
          model = jsonencode({
            datasource = data.value.datasource
            queryType  = "range"
            editorMode = "code"
            expr       = replace(regex(local.regex_query, data.value["query"])[0], "\n", "")
            # intervalMs    = data.value["depth_seconds"]
            maxDataPoints = 43200
            refId         = "QUERY"
          })
        }
      }

      dynamic "data" {
        for_each = can(rule.value.expressions) ? [for expr in rule.value.expressions : expr] : []
        content {
          relative_time_range {
            from = "0" #can(data.value.type) ? (data.value.type == "threshold" ? "600" : "1000") : "1000"
            to   = "0"
          }
          datasource_uid = "__expr__"
          ref_id         = can(data.value.type) ? (data.value.type == "threshold" ? "ALERTCONDITION" : "QUERY_RESULT") : "QUERY_RESULT"

          model = jsonencode({
            conditions = flatten([
              # Условия для reduce
              can(data.value.type) && data.value.type == "reduce" ? [{
                evaluator = {
                  params = []
                  type   = "gt"
                }
                operator = {
                  type = "and"
                }
                query = {
                  params = []
                }
                reducer = {
                  params = []
                  type   = "last"
                }
                type = "query"

              }] : [],
              # Условия для threshold
              can(data.value.type) && data.value.type == "threshold" ? [{
                evaluator = {
                  params = [tonumber(regex(local.regex_query, rule.value["query"])[2])]
                  type   = local.operator_translation[regex(local.regex_query, rule.value["query"])[1]]
                }
                operator = {
                  type = "and"
                }
                query = {
                  params = ["QUERY_RESULT"] # см комент для expression
                }
                reducer = {
                  params = []
                  type   = "last"
                }
                type = "query"
              }] : []
            ])
            datasource = {
              type = "__expr__"
              uid  = "__expr__"
            }
            reducer       = (data.value.type == "reduce" ? "last" : "")
            expression    = data.value.type == "threshold" ? "QUERY_RESULT" : "QUERY" # поправить если один threshold то должно быть "QUERY"
            hide          = false
            intervalMs    = 1000
            maxDataPoints = 43200
            refId         = data.value.type == "threshold" ? "ALERTCONDITION" : "QUERY_RESULT"
            type          = data.value.type
          })
        }
      }
    }
  }
}
