#!/bin/bash
# https://help.launchpad.net/API/SigningRequests
# https://api.launchpad.net/

oauth_consumer_key=${oauth_consumer_key:=oem-scripts}

# shellcheck source=config.sh
source /usr/share/oem-scripts/config.sh 2>/dev/null || source config.sh

get_token()
{
    echo "oauth_consumer_key=${oauth_consumer_key}"
    oauth=$(http --form post https://launchpad.net/+request-token oauth_consumer_key="$oauth_consumer_key" oauth_signature_method=PLAINTEXT oauth_signature="&")
    echo "$oauth"

    eval "${oauth/&*/}"
    echo "oauth_token=${oauth_token:=}"

    eval "${oauth/*&/}"
    echo "oauth_token_secret=${oauth_token_secret:=}"

    echo "Please open https://launchpad.net/+authorize-token?oauth_token=$oauth_token to authorize the token."

    while :; do
        body=$(http --form post https://launchpad.net/+access-token oauth_token="$oauth_token" oauth_consumer_key="$oauth_consumer_key" oauth_signature_method=PLAINTEXT oauth_signature="&$oauth_token_secret")
        if [ "$body" = "Request token has not yet been reviewed. Try again later." ]; then
            echo "Wait for 5 seconds."
            sleep 5
        elif [ "$body" = "Invalid OAuth signature." ]; then
            break
        else
            echo "$body"
            oauth=${body/&lp.context=*/}
            eval "${oauth/&*/}"
            echo "oauth_token=${oauth_token}"

            eval "${oauth/*&/}"
            echo "oauth_token_secret=${oauth_token_secret}"
            break
        fi
    done
}

get_api()
{
    api="$1" && shift
    http --follow GET "https://api.launchpad.net/$api" \
        'OAuth realm'=="https://api.launchpad.net/" \
        oauth_consumer_key=="${oauth_consumer_key}" \
        oauth_nonce=="$(date +%s)" \
        oauth_signature=="&${oauth_token_secret}" \
        oauth_signature_method=="PLAINTEXT" \
        oauth_timestamp=="$(date +%s)" \
        oauth_token=="${oauth_token}" \
        oauth_version=="1.0" \
        "$@"
}

post_api()
{
    api="$1" && shift
    http --form POST "https://api.launchpad.net/$api" \
        'OAuth realm'="https://api.launchpad.net/" \
        oauth_consumer_key="${oauth_consumer_key}" \
        oauth_nonce="$(date +%s)" \
        oauth_signature="&${oauth_token_secret}" \
        oauth_signature_method="PLAINTEXT" \
        oauth_timestamp="$(date +%s)" \
        oauth_token="${oauth_token}" \
        oauth_version="1.0" \
        "$@"
}


if has_oem_scripts_config; then
    oauth_token=$(read_oem_scripts_config oauth_token)
    oauth_token_secret=$(read_oem_scripts_config oauth_token_secret)
else
    get_token
    write_oem_scripts_config oauth_token "${oauth_token}"
    write_oem_scripts_config oauth_token_secret "${oauth_token_secret}"
fi

case "$1" in
    ("get"|"GET")
        shift
        get_api "$@"
        ;;
    ("post"|"POST")
        shift
        post_api "$@"
        ;;
    (*)
        get_api devel/people/+me
        ;;
esac
