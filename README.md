# aws-sso-switcher
Script for on-the-fly switching between temporary AWS credentials through AWS SSO.

## Description
I wrote this script to make it easier for me to switch between temporary AWS credentials of many different AWS accounts. At the time of this writing, the AWS Cli v2 does provide this mechanism, however it is required to create an AWS Profile for each account, which is not practical if you're working with many accounts and/or multiple instances of AWS SSO.

## Features

* Creates profiles for different instances of AWS SSO
* Requests the required access token through the SSO OIDC workflow
* Refreshes the access token when the current one expires

## Requirements

* AWS Cli v2
* jq
* fzf

## Setup

Simply clone this repository and run the script. Since the script is not made to be sourced, it simply prints the required `export` commands for the AWS credential environment variables. You can set up a function in your `.bashrc` or `.zshrc` file that can run the export commands like so:

```
aws-sso-switcher() {
  path/to/your/aws-sso-switcher.sh "$@" | while read -r line; do 
    if [[ $line =~ ^export ]]; then
      eval $line
    else
      echo $line
    fi
  done
}
```

## Usage

```
Usage: aws-sso-switcher [options]

Helps you fetch temporary credentials to different AWS accounts supplied by AWS SSO.
Requires fzf and jq.

Options:
-p   Your SSO profile. Upon running the script for the first time, it will set one up for you.
-a   Add another SSO profile.
-c   The path for the SSO profile config file.
-h   Print this message.
```