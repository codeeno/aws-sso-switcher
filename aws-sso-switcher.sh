#!/bin/bash

set -euo pipefail

function printHelp() {
   echo
   echo "Usage: aws-sso-switcher [options]"
   echo
   echo "Helps you fetch temporary credentials to different AWS accounts supplied by AWS SSO."
   echo "Requires fzf and jq."
   echo
   echo "Options:"
   echo "-p   Your SSO profile. Upon running the script for the first time, it will set one up for you."
   echo "-a   Add another SSO profile."
   echo "-c   The path for the SSO profile config file."
   echo "-h   Print this message."
}

function parseOpts() {
  config_path="$HOME/.aws_sso_switcher"
  add_profile=false
  profile=''

  local OPTIND
  while getopts ':ahp:c:' opt; do
    case "$opt" in
      p)
        profile=$OPTARG
        ;;
      a)
        add_profile='true'
        ;;
      c)
        config_path=$OPTARG
        ;;
      h)
        printHelp
        exit 0
        ;;
      :)
        printf "\nMissing option for flag: -$OPTARG\n"
        printhelp
        exit 1
        ;;
      *)
        printf "\nUnexpected option: -$OPTARG\n"
        printhelp
        exit 1
        ;;
    esac
  done
  shift $((OPTIND -1))
}

function validateOpts() {
  if [[ -z "$profile" ]] && [[ $add_profile == true ]]
  then
    addProfile
    exit 0
  fi

  if [[ -z "$profile" ]] && [[ $add_profile == false ]]
  then
    printf "\nInvalid options. Either the -p or -a option is required.\n"
    exit 1
  fi

  if [[ ! -z "$profile" ]] && [[ $add_profile == true ]]
  then
    printf "\nInvalid options. Please set only one of: -a, -p.\n"
    exit 1
  fi
}

function addProfile() {
  read -p "Name of your SSO profile: " profile_name
  read -p "Your SSO Start URL (e.g. https://<your-alias>.awsapps.com/start): " start_url
  read -p "Your AWS Region: " region

  local new_config=$(jq \
    --arg profileName $profile_name \
    --arg startUrl $start_url \
    --arg region $region \
    '.+ {($profileName): {"startUrl": $startUrl, region: $region, accessToken: "", accessTokenExpiry: "0"}}' \
    $config_path)
  echo "$new_config" > $config_path
  printf "\nNew profile created.\n"
}

function initConfig() {
  if [[ ! -e $config_path ]]; then
    echo "{}" > $config_path
    addProfile
    exit 0
  fi
}

function updateConfig() {
  printf "Updating Config...\n"
  local new_config=$(jq \
    --arg profile "$profile" \
    --arg newAccessToken "$1" \
    --arg newAccessTokenExpiry "$(date -v +$2S +%s)" \
    '.[$profile].accessToken=$newAccessToken | .[$profile].accessTokenExpiry=$newAccessTokenExpiry' \
    $config_path)
  echo "$new_config" > $config_path
}

function readConfig() {
  printf "Loading Config...\n"
  read region start_url access_token access_token_expiry < <(echo $( \
    jq --arg profile "$profile" '.[$profile]' $config_path \
    | jq -r '"\(.region) \(.startUrl) \(.accessToken) \(.accessTokenExpiry)"'))
}

function checkAccessTokenExpiry() {
  printf "Check if access token still valid...\n"
  token_expiry=$(jq -r \
    --arg profile "$profile" \
    '.[$profile].accessTokenExpiry' \
    $config_path)

  if (( $(date +%s) >= $token_expiry)); then
    printf "Access token is expired. Getting new access token...\n"
    refreshAccessToken
  fi
}

function refreshAccessToken() {

  printf "Register Client...\n"
  read client_id client_secret < <(echo $( \
    aws sso-oidc register-client \
    --client-name $(hostname) \
    --client-type public \
    --region $region \
    | jq -r '.clientId, .clientSecret'))

  printf "Start Device Authorization...\n"
  read device_code verification_uri_complete < <(echo $( \
    aws sso-oidc start-device-authorization \
    --client-id $client_id \
    --client-secret $client_secret \
    --start-url $start_url \
    --region $region \
    | jq -r '.deviceCode, .verificationUriComplete'))

  printf "\n\
####################\n\n\
Please visit the following URL in your browser:\n\
$verification_uri_complete\n\n\
Once done, press [Enter]\n\n\
####################\n\n" 
  read -s

  printf "Requesting Access Token...\n"
  read access_token access_token_expiry < <(echo $( \
    aws sso-oidc create-token \
    --client-id $client_id \
    --client-secret $client_secret \
    --grant-type 'urn:ietf:params:oauth:grant-type:device_code' \
    --device-code $device_code \
    --region $region \
    | jq -r '.accessToken, .expiresIn'))

  updateConfig $access_token $access_token_expiry
}

function getCredentials() {
  printf "Acquiring Credentials...\n"

  account_list=$(aws sso list-accounts \
   --access-token $access_token \
   --region $region)
  account_name=$(echo $account_list | jq '.accountList[]' | jq -r '.accountName' | fzf)
  account_id=$(echo $account_list | jq -r ".accountList[] | select(.accountName==\"$account_name\") | .accountId")

  roles_list=$(aws sso list-account-roles \
    --access-token $access_token \
    --account-id $account_id \
    --region $region)
  role_name=$(echo $roles_list | jq '.roleList[]' | jq -r '.roleName' | fzf)

  credentials=$(aws sso get-role-credentials \
    --access-token $access_token \
    --role-name $role_name \
    --account-id $account_id \
    --region $region \
    | jq '.roleCredentials')
}

function main() {
  parseOpts "$@"
  initConfig
  validateOpts
  readConfig
  checkAccessTokenExpiry
  getCredentials

  echo "export AWS_ACCESS_KEY_ID=$(echo $credentials | jq -r '.accessKeyId')"
  echo "export AWS_SECRET_ACCESS_KEY=$(echo $credentials | jq -r '.secretAccessKey')"
  echo "export AWS_SESSION_TOKEN=$(echo $credentials | jq -r '.sessionToken')"
  printf "All set!\n"
}

main "$@"

