# Automate Let’s Encrypt Wildcard Certificate Renewal via DNS Authentication for Hosting.DE

I am using provider https://hosting.de currently for some cloud resources.

A nice thing about hosting.de is that they offer a **REST API** (https://www.hosting.de/api/#listing-zones) to interact with their DNS system.
Such API allows automation of certificate renewals even for Let’s Encrypt **wildcard domain** certificates.

Such renewals require "dns" authentication. The certification authority requests some TXT records be put into DNS (random nonces),
from where they're read back for verification. Seeing these random values in DNS "proves" to the CA that you're indeed in control
of the domain that you're asking a certificate for.

This repository contains two small scripts which can interface between [Certbot](https://certbot.eff.org/) and Hosting.DE

# Calling Certbot with Hooks

    certbot certonly --noninteractive --manual --preferred-challenges dns \
       --manual-auth-hook    ./certbot-hook-scripts-hosting-de/certbot-authenticator.sh \
       --manual-cleanup-hook ./certbot-hook-scripts-hosting-de/certbot-cleanup.sh \
       -d '*.example.de' -d 'example.de' \
       --post-hook "service lighttpd restart"

# What do these hook scripts do?

* certbot-authenticator.sh is called by certbot with CERTBOT_DOMAIN (domain name, wildcard stripped, if any) and CERTBOT_VALIDATION (the random nonce)
and will put the nonce into DNS under TXT `_acme-challenge.${CERTBOT_DOMAIN}`.

* certbot-cleanup.sh reads all TXT `_acme-challenge.${CERTBOT_DOMAIN}` records and issues a deletion API call.
# API Key and URL

Create an **API Key** in the Hosting.DE Web UI under https://secure.hosting.de/profile, which has (__at least__, or better __exactly__) below two permissions:

* DNS-Service
    * Zonen - Anzeigen
    * Zonen - Bearbeiten

Create a configuration file with these credentials, e.g. like so:

    cat - > /etc/certbot-authenticator.cfg <<END
    # Credentials for .../certbot-hook-scripts-hosting-de/certbot-authenticator.sh
    url=https://secure.hosting.de/api/dns/v1/json
    key=<your API key>
    END

    chmod 400 /etc/certbot-authenticator.cfg

# Automate using Cron

You will want to create a scheduled Job (Cron, or systemctl timer) that calls certbot regulary, e.g. weekly, so that expiring certificates are replaced in a timely manner.

The web server config (e.g. lighttpd, or Apache, Nginx, ...) should be changed to point to the certbot-provided certificate and private key locations, e.g.

    ssl.pemfile = "/etc/letsencrypt/live/example.de/fullchain.pem"
    ssl.privkey = "/etc/letsencrypt/live/example.de/privkey.pem"

# Testing

You can run the scripts without certbot by supplying the required env variables explicitly:

    CERTBOT_DOMAIN=example.de CERTBOT_VALIDATION=SomeRandomValue1234 ./certbot-authenticator.sh

Check TXT records have been stored OK, e.g. with

    host -t TXT _acme-challenge.example.de ns1.hosting.de

Clean up again:

    CERTBOT_DOMAIN=example.de ./certbot-cleanup.sh

# Caveat

I have a feeling that there must be a pre-existing solution for this use case, even for provider Hosting.DE?
The [Certbot 3rd-party plugin list](https://eff-certbot.readthedocs.io/en/stable/using.html#third-party-plugins)
does show a number of plugins, but it wasn't immediately obvious to me which one would meet the API requirements for Hosting.DE.

Please let me know if I missed something there.

# Security

There is one drawback to this approach that should be noted: the API Key still is way too powerful. It could be used to modify not only TXT records, but all the zone's records, including A and AAAA records. If this script runs right on the web server machine then a compromise to that machine will give access to the API key which in turn will give access to most of the domain, including a complete redirect option.

To some extent, this is down to the limited configurability of the API key in Hosting.DE's system. It's not possible to restrict the key to, say, just TXT records or even TXT `_acme-challenge.${CERTBOT_DOMAIN}` records. What **is** possible in their system, though, is to restrict the API key's use to a set of source IPs. This is great (and goes beyond what other providers offer), as a leaked key may not easily be usable elsewhere.

How to improve on this? Another approach supported by ACME is to delegate retrieval of just the challenge TXT records through a CNAME delegation to some (ephemeral) DNS server. See https://github.com/joohoi/acme-dns for such an approach. That comes with it's own caveats, though.

Stay safe!
