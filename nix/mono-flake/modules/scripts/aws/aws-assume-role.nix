{ inputs, globals, pkgs, machine-config, lib, ... }:

let

  aws-assume-role = pkgs.writeText "aws-assume-role.sh" ''
  aws-assume-role () {
    local account_id=""
    local role_name=""
    local session_name="assumed-role-session-$(date +%s)"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
      case $1 in
        --account-id)
          account_id="$2"
          shift 2
          ;;
        --role-name)
          role_name="$2"
          shift 2
          ;;
        *)
          echo "Unknown option: $1"
          echo "Usage: assume_role [--account-id ACCOUNT_ID] [--role-name ROLE_NAME]"
          return 1
          ;;
      esac
    done

    # Prompt for account ID if not provided
    if [[ -z "$account_id" ]]; then
      if [[ -n "$BASH_VERSION" ]]; then
          read -p "Enter AWS Account ID: " account_id
      elif [[ -n "$ZSH_VERSION" ]]; then
          read "account_id?Enter AWS Account ID: "
      fi
      if [[ -z "$account_id" ]]; then
        echo "Error: Account ID is required"
        return 1
      fi
    fi

    # Prompt for role name if not provided
    if [[ -z "$role_name" ]]; then
      if [[ -n "$BASH_VERSION" ]]; then
          read -p "Enter Role Name: " role_name
      elif [[ -n "$ZSH_VERSION" ]]; then
          read "role_name?Enter Role Name: "
      fi
      if [[ -z "$role_name" ]]; then
        echo "Error: Role name is required"
        return 1
      fi
    fi

    # Construct the role ARN
    local role_arn="arn:aws:iam::''${account_id}:role/''${role_name}"

    echo "Assuming role: $role_arn"

    # Assume the role and capture credentials
    local assume_output
    assume_output=$(aws sts assume-role \
      --role-arn "$role_arn" \
      --role-session-name "$session_name" \
      --output text \
      --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken,Expiration]' 2>&1)

    if [[ $? -ne 0 ]]; then
      echo "Error assuming role:"
      echo "$assume_output"
      return 1
    fi

    # Parse the tab-separated output
    export AWS_ACCESS_KEY_ID=$(echo "$assume_output" | awk '{print $1}')
    export AWS_SECRET_ACCESS_KEY=$(echo "$assume_output" | awk '{print $2}')
    export AWS_SESSION_TOKEN=$(echo "$assume_output" | awk '{print $3}')
    local expiration=$(echo "$assume_output" | awk '{print $4}')

    # Check if credentials were successfully extracted
    if [[ -z "$AWS_ACCESS_KEY_ID" ]]; then
      echo "Error: Failed to extract credentials from assume-role response"
      return 1
    fi

    echo "Successfully assumed role!"
    echo "Credentials are valid until: $expiration"
    echo ""
    echo "The following environment variables have been set:"
    echo "  AWS_ACCESS_KEY_ID"
    echo "  AWS_SECRET_ACCESS_KEY"
    echo "  AWS_SESSION_TOKEN"
    echo ""
    echo "To verify, run: aws sts get-caller-identity"

    exit 0
  }
  '';
in

{
  environment.interactiveShellInit = ''
  source ${aws-assume-role}
  '';
}