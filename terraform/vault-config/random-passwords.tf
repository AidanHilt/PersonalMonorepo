resource "random_password" "generated" {
  for_each = merge([
    for secret_name, secret in local.secret_definitions : {
      for key, config in secret.data :
        "${secret_name}-${key}" => merge(
          {
            length  = lookup(config, "postgres_password", false) ? 64 : 32
            special = lookup(config, "postgres_password", false) ? true : false
          },
          config
        )
        if !can(config.value) || config.value == null
    }
  ]...)

  length  = each.value.length
  special = each.value.special
}