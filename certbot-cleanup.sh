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

# Certbot script (cleanup) to support ACME for https://hosting.de (DNS-based challenges, e.g. for wildcard certificates)

# Environment passed in from certbot:
# CERTBOT_DOMAIN=<fqdn> (note that for wildcard certs/domains, this is without the leading '*.')

if [ -z "${CERTBOT_DOMAIN}" ]; then
  >&2 echo "CERTBOT_DOMAIN undefinded. Note this script is intended to be called from certbot via --manual-auth-hook."
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

# Query the API for all zone records. We're filtering via jq in the next step, so no need to be selective here.
# Extract the IDs of all TXT records and put them into a JSON array with {"id": ..id.. } elements.
IDS_TO_DELETE=$(http --check-status --body POST "${URL}/zonesFind" <<END|
{
    "authToken": "${AUTH_TOKEN}",
    "filter": {
        "field": "recordName",
        "value": "${CERTBOT_DOMAIN}"
    },
    "limit": 1
}
END
jq "[select(.status==\"success\") | .response.data[0].records[] | select(.type==\"TXT\") | select(.name==\"_acme-challenge.${CERTBOT_DOMAIN}\") | {\"id\" : .id}]")

# If any are found, go ahead and delete them.
RESULT="success"
if [ -n "${IDS_TO_DELETE}" -a "[]" != "${IDS_TO_DELETE}" ]; then
  RESULT=$(http --check-status --body POST "${URL}/recordsUpdate" <<END|
  {
      "authToken": "${AUTH_TOKEN}",
      "zoneName": "${CERTBOT_DOMAIN}",
      "recordsToDelete": ${IDS_TO_DELETE}
  }
END
  jq -r .status)
fi

if [ "${RESULT}" == "success" ]; then
  echo "OK"
elif [ "${RESULT}" == "pending" ]; then
  echo "OK (sleep 10)"
  sleep 10
else
  >&2 echo "Failed to cleanup TXT record(s) for ${CERTBOT_DOMAIN} (${RESULT})"
  exit 3
fi

# END
