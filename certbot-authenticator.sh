#!/bin/bash -e

# Copyright 2023 Matthias Gaertner
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Certbot script (authenticator) to support ACME for https://hosting.de (DNS-based challenges, e.g. for wildcard certificates)

# Environment passed in from certbot:
# CERTBOT_DOMAIN=<fqdn> (note that for wildcard certs/domains, this is without the leading '*.')
# CERTBOT_VALIDATION=<random token>

if [ -z "${CERTBOT_DOMAIN}" ]; then
  >&2 echo "CERTBOT_DOMAIN undefinded. Note this script is intended to be called from certbot via --manual-auth-hook."
  exit 2
fi
if [ -z "${CERTBOT_VALIDATION}" ]; then
  >&2 echo "CERTBOT_VALIDATION undefinded. Note this script is intended to be called from certbot via --manual-auth-hook."
  exit 2
fi

CFG_FILE="${CFG_FILE:=/etc/certbot-authenticator.cfg}"
if [ ! -r "${CFG_FILE}" ]; then
  >&2 echo "Unable to read config file $CFG_FILE, abort"
  exit 2
fi

URL=$(grep ^url= "${CFG_FILE}" | cut -d '=' -f 2-)
AUTH_TOKEN=$(grep ^key= "${CFG_FILE}" | cut -d '=' -f 2-)

if [ -z "${URL}" ]; then
  >&2 echo "Unable to read url from config file $CFG_FILE, abort"
  exit 2
fi

if [ -z "${AUTH_TOKEN}" ]; then
  >&2 echo "Unable to read key from config file $CFG_FILE, abort"
  exit 2
fi

RESULT=$(http --check-status --body POST "${URL}/recordsUpdate" <<END|
{
    "authToken": "${AUTH_TOKEN}",
    "zoneName": "${CERTBOT_DOMAIN}",
    "recordsToAdd": [
        {
            "name": "_acme-challenge.${CERTBOT_DOMAIN}",
            "type": "TXT",
            "content": "${CERTBOT_VALIDATION}",
            "ttl": 720
        }
    ]
}
END
jq -r .status)

if [ "${RESULT}" == "success" ]; then
  echo "OK"
elif [ "${RESULT}" == "pending" ]; then
  echo "OK (sleep 10)"
  sleep 10
else
  >&2 echo "Failed to add TXT record for ${CERTBOT_DOMAIN} (${RESULT})"
  exit 3
fi

# END
