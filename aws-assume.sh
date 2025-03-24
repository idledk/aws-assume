#!/bin/bash

#set -x

# Check if the AWS CLI is installed
if ! command -v aws &> /dev/null
then
    echo "Error: The AWS CLI is not installed."
    exit 1
fi

# Check if the jq command is installed
if ! command -v jq &> /dev/null
then
    echo "Error: The jq command is not installed."
    exit 1
fi

source "assume-accounts"

# Set the variables for the script

select AWS_ASSUME_PROFILE in ${!role_list[@]}; do
  [[ -n "$AWS_ASSUME_PROFILE" ]] && break # Valid selection made, exit the menu.
  echo ">>> Invalid Selection" >&2;
done

echo "Assuming account $AWS_ASSUME_PROFILE"

read -p "Enter the AWS account profile [default]: " AWS_AWS_ASSUME_PROFILE
AWS_AWS_ASSUME_PROFILE=${AWS_PROFILE:-default}

function account_exists () {
  if [[ -n "${role_list[$1]:-}" ]]; then
    return 1
  fi
}

function account_id () {
  echo "${role_list[$1]}" | cut -d'|' -f 1
}

function role () {
  echo "${role_list[$1]}" | cut -d'|' -f 2
}

function region () {
  echo "${role_list[$1]}" | cut -d'|' -f 3
}

function description () {
  echo "${role_list[$1]}" | cut -d'|' -f 4
}

# Simple sanity check of entered account profile
account_exists "$AWS_ASSUME_PROFILE"
if [ $? -eq 1 ]
then
  echo "Account found"
else
  echo "Account not found in list"
  exit 1
fi

ACCOUNT_ID="$(account_id "$AWS_ASSUME_PROFILE")"
REGION="$(region "$AWS_ASSUME_PROFILE")"
ROLE="$(role "$AWS_ASSUME_PROFILE")"
DESCRIPTION="$(description "$AWS_ASSUME_PROFILE")"

echo "Account: $ACCOUNT_ID"
echo "Region: $REGION"
echo "Role: $ROLE"
echo "Description: $DESCRIPTION"

# Get the MFA serial number and token
# read -p "Enter the MFA serial number (e.g. arn:aws:iam::123456789012:mfa/user): " MFA_SERIAL
read -p "Enter the MFA token: " MFA_TOKEN

# Get the temporary credentials
CREDS=$(aws sts assume-role --profile $AWS_AWS_ASSUME_PROFILE --role-arn "arn:aws:iam::$ACCOUNT_ID:role/$ROLE" --serial-number "$MFA_SERIAL" --token-code "$MFA_TOKEN" --duration-seconds 3600 --role-session-name $SESSION_NAME)

if [ $? -ne 0 ]
then
  echo "AWS auth failure. Exiting"
  exit 1
fi

# Extract the access key, secret key, and session token from the JSON output
ACCESS_KEY=$(echo "$CREDS" | jq -r .Credentials.AccessKeyId)
SECRET_KEY=$(echo "$CREDS" | jq -r .Credentials.SecretAccessKey)
SESSION_TOKEN=$(echo "$CREDS" | jq -r .Credentials.SessionToken)

# Set the temporary credentials as the default AWS CLI profile
aws configure set aws_access_key_id "$ACCESS_KEY" --profile "$AWS_ASSUME_PROFILE"
aws configure set aws_secret_access_key "$SECRET_KEY" --profile "$AWS_ASSUME_PROFILE"
aws configure set aws_session_token "$SESSION_TOKEN" --profile "$AWS_ASSUME_PROFILE"
aws configure set region "$REGION" --profile "$AWS_ASSUME_PROFILE"


echo "You should really set your default AWS profile: "
echo "export AWS_DEFAULT_PROFILE=$AWS_ASSUME_PROFILE"

echo "Successfully assumed role $ROLE_NAME in account $ACCOUNT_ID with MFA."

