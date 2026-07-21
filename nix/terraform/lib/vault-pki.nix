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

    let
      sanitize = s: builtins.replaceStrings [ "." "-" ] [ "_" "_" ] s;
      safeHostname = sanitize hostname;
    in

    {
      variable = {
        "${environment}" = {
          type = "bool";
          description = "Create resources based on configuration of environment ${environment}";
          default = false;
        };
      };

      resource = {
        vault_mount."pki_root_${safeHostname}" = {
          count = "\${var.${environment} ? 1 : 0}";
          path                      = "pki_${safeHostname}";
          type                      = "pki";
          description               = "Root CA for ${hostname}";
          max_lease_ttl_seconds     = 315360000;
          default_lease_ttl_seconds = 315360000;
        };

        vault_pki_secret_backend_root_cert."root_${safeHostname}" = {
          count = "\${var.${environment} ? 1 : 0}";
          backend     = "\${vault_mount.pki_root_${safeHostname}[0].path}";
          type        = "internal";
          common_name = hostname;
          ttl         = rootTtl;
        };

        vault_pki_secret_backend_config_urls.root_urls = {
          count = "\${var.${environment} ? 1 : 0}";
          backend                 = "\${vault_mount.pki_root_${safeHostname}[0].path}";
          issuing_certificates    = [ "${vaultAddr}/v1/pki/ca" ];
          crl_distribution_points = [ "${vaultAddr}/v1/pki/crl" ];
        };

        vault_mount."pki_int_${safeHostname}" = {
          count = "\${var.${environment} ? 1 : 0}";
          path                      = "pki_int_${safeHostname}";
          type                      = "pki";
          description               = "Intermediate CA for cert-manager (${hostname})";
          max_lease_ttl_seconds     = 157680000;
          default_lease_ttl_seconds = 157680000;
        };

        vault_pki_secret_backend_intermediate_cert_request."int_${safeHostname}" = {
          count = "\${var.${environment} ? 1 : 0}";
          backend     = "\${vault_mount.pki_int_${safeHostname}[0].path}";
          type        = "internal";
          common_name = "${hostname} Intermediate Authority";
        };

        vault_pki_secret_backend_root_sign_intermediate."int_signed_${safeHostname}" = {
          count = "\${var.${environment} ? 1 : 0}";
          backend     = "\${vault_mount.pki_root_${safeHostname}[0].path}";
          csr         = "\${vault_pki_secret_backend_intermediate_cert_request.int_${safeHostname}[0].csr}";
          common_name = "${hostname} Intermediate Authority";
          ttl         = intTtl;
        };

        vault_pki_secret_backend_intermediate_set_signed."int_set_signed_${safeHostname}" = {
          count = "\${var.${environment} ? 1 : 0}";
          backend     = "\${vault_mount.pki_int_${safeHostname}[0].path}";
          certificate = "\${vault_pki_secret_backend_root_sign_intermediate.int_signed_${safeHostname}[0].certificate}";
        };

        vault_pki_secret_backend_config_urls."int_urls_${safeHostname}" = {
          count = "\${var.${environment} ? 1 : 0}";
          backend                 = "\${vault_mount.pki_int_${safeHostname}[0].path}";
          issuing_certificates    = [ "${vaultAddr}/v1/pki_int/ca" ];
          crl_distribution_points = [ "${vaultAddr}/v1/pki_int/crl" ];
        };

        vault_pki_secret_backend_role."cert_manager_${safeHostname}" = {
          count = "\${var.${environment} ? 1 : 0}";
          backend                    = "\${vault_mount.pki_int_${safeHostname}[0].path}";
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

        vault_policy."cert_manager_${safeHostname}" = {
          count = "\${var.${environment} ? 1 : 0}";
          name = "cert-manager-policy-${hostname}";
          policy = ''
            path "''${vault_mount.pki_int_${safeHostname}[0].path}/sign/''${vault_pki_secret_backend_role.cert_manager_${safeHostname}[0].name}" {
              capabilities = ["create", "update"]
            }
            path "''${vault_mount.pki_int_${safeHostname}[0].path}/issue/''${vault_pki_secret_backend_role.cert_manager_${safeHostname}[0].name}" {
              capabilities = ["create"]
            }
          '';
        };

        vault_kubernetes_auth_backend_role."cert_manager_${safeHostname}" = {
          count = "\${var.${environment} ? 1 : 0}";
          # TODO this may bite us in the ass if we can't assume that this is run with the main vault setup, in which case
          # we need to switch between data.vault_auth and resource.vault_auth based on whether or not we're standalone
          backend                           = "\${data.vault_auth_backend.kubernetes.path}";
          role_name                         = "cert-manager-${safeHostname}";
          bound_service_account_names       = [ certManagerSA ];
          bound_service_account_namespaces  = [ certManagerNamespace ];
          token_policies                    = [ "\${vault_policy.cert_manager_${safeHostname}[0].name}" ];
          token_ttl                         = 3600;
        };
      };

      output."pki_int_issue_path_${safeHostname}" = {
        value = "\${try(\"vault_mount.pki_int_${safeHostname}[0].path}/sign/\${vault_pki_secret_backend_role.cert_manager_${safeHostname}[0].name}\", null)}";
      };
    };

    mkPkiStackForEnv = envs:
      let
        envResults = lib.mapAttrsToList
          (envName: envConfig:
            if !(envConfig ? hostnames) then
              throw "mkPkiStackForEnv: environment '${envName}' is missing required 'hostnames' key"
            else
              let
                hostResults = map
                  (hostname: mkVaultPkiCertManager {inherit hostname; environment=envName;})
                  envConfig.hostnames;
              in
              lib.foldl' lib.recursiveUpdate { } hostResults
          )
          envs;
      in
      lib.foldl' lib.recursiveUpdate { } envResults;
in
{
  inherit mkVaultPkiCertManager mkPkiStackForEnv;
}
