{ lib, ... }:

let
  mkVaultPkiCertManager =
    { hostname
    , environment
    , vaultAddr           ? "http://vault.${hostname}"
    , kubernetesHost       ? "https://kubernetes.default.svc:443"
    , certManagerNamespace ? "cert-manager"
    , certManagerSA        ? "cert-manager"
    , rootTtl              ? "87600h"   # 10y
    , intTtl               ? "43800h"   # 5y
    , roleMaxTtl           ? "720h"     # 30d
    , allowWildcard        ? false
    }:

    {
      variable = {
        "${environment}" = {
          type = "bool";
          description = "Create resources based on configuration of environment ${environment}";
          default = false;
        };
      };

      resource = {
        vault_mount."pki_root_${hostname}" = {
          count = "\${var.${environment} ? 1 : 0}";
          path                      = "pki_${hostname}";
          type                      = "pki";
          description               = "Root CA for ${hostname}";
          max_lease_ttl_seconds     = 315360000;
          default_lease_ttl_seconds = 315360000;
        };

        vault_pki_secret_backend_root_cert."root_${hostname}" = {
          count = "\${var.${environment} ? 1 : 0}";
          backend     = "\${vault_mount.pki_root_${hostname}.path}";
          type        = "internal";
          common_name = hostname;
          ttl         = rootTtl;
        };

        vault_pki_secret_backend_config_urls.root_urls = {
          count = "\${var.${environment} ? 1 : 0}";
          backend                 = "\${vault_mount.pki_root_${hostname}.path}";
          issuing_certificates    = [ "${vaultAddr}/v1/pki/ca" ];
          crl_distribution_points = [ "${vaultAddr}/v1/pki/crl" ];
        };

        vault_mount."pki_int_${hostname}" = {
          count = "\${var.${environment} ? 1 : 0}";
          path                      = "pki_int_${hostname}";
          type                      = "pki";
          description               = "Intermediate CA for cert-manager (${hostname})";
          max_lease_ttl_seconds     = 157680000;
          default_lease_ttl_seconds = 157680000;
        };

        vault_pki_secret_backend_intermediate_cert_request."int_${hostname}" = {
          count = "\${var.${environment} ? 1 : 0}";
          backend     = "\${vault_mount.pki_int_${hostname}.path}";
          type        = "internal";
          common_name = "${hostname} Intermediate Authority";
        };

        vault_pki_secret_backend_root_sign_intermediate."int_signed_${hostname}" = {
          count = "\${var.${environment} ? 1 : 0}";
          backend     = "\${vault_mount.pki_root_${hostname}.path}";
          csr         = "\${vault_pki_secret_backend_intermediate_cert_request.int_${hostname}.csr}";
          common_name = "${hostname} Intermediate Authority";
          ttl         = intTtl;
        };

        vault_pki_secret_backend_intermediate_set_signed."int_set_signed_${hostname}" = {
          count = "\${var.${environment} ? 1 : 0}";
          backend     = "\${vault_mount.pki_int_${hostname}.path}";
          certificate = "\${vault_pki_secret_backend_root_sign_intermediate.int_signed_${hostname}.certificate}";
        };

        vault_pki_secret_backend_config_urls."int_urls_${hostname}" = {
          count = "\${var.${environment} ? 1 : 0}";
          backend                 = "\${vault_mount.pki_int.path}";
          issuing_certificates    = [ "${vaultAddr}/v1/pki_int/ca" ];
          crl_distribution_points = [ "${vaultAddr}/v1/pki_int/crl" ];
        };

        vault_pki_secret_backend_role."cert_manager_${hostname}" = {
          count = "\${var.${environment} ? 1 : 0}";
          backend                    = "\${vault_mount.pki_int_${hostname}.path}";
          name                       = "cert-manager";
          allowed_domains            = [ hostname ];
          allow_subdomains           = true;
          allow_bare_domains         = true;
          allow_glob_domains         = false;
          allow_wildcard_certificates = allowWildcard;
          allow_ip_sans              = true;
          max_ttl                    = roleMaxTtl;
          key_type                   = "rsa";
          key_bits                   = 2048;
        };

        vault_policy."cert_manager_${hostname}" = {
          count = "\${var.${environment} ? 1 : 0}";
          name = "cert-manager-policy-${hostname}";
          policy = ''
            path "''${vault_mount.pki_int_${hostname}.path}/sign/''${vault_pki_secret_backend_role.cert_manager_${hostname}.name}" {
              capabilities = ["create", "update"]
            }
            path "''${vault_mount.pki_int_${hostname}.path}/issue/''${vault_pki_secret_backend_role.cert_manager_${hostname}.name}" {
              capabilities = ["create"]
            }
          '';
        };

        vault_kubernetes_auth_backend_role."cert_manager_${hostname}" = {
          count = "\${var.${environment} ? 1 : 0}";
          backend                           = "\${vault_auth_backend.kubernetes.path}";
          role_name                         = "cert-manager";
          bound_service_account_names       = [ certManagerSA ];
          bound_service_account_namespaces  = [ certManagerNamespace ];
          token_policies                    = [ "\${vault_policy.cert_manager_${hostname}.name}" ];
          token_ttl                         = 3600;
        };
      };

      output."pki_int_issue_path_${hostname}" = {
        count = "\${var.${environment} ? 1 : 0}";
        value = "\${vault_mount.pki_int.path}/sign/\${vault_pki_secret_backend_role.cert_manager.name}";
      };
    };
in
{
  inherit mkVaultPkiCertManager;
}
