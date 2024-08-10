#!/bin/bash

# Update and install required packages
sudo apt update
sudo apt install -y postfix dovecot-core dovecot-imapd spamassassin fail2ban certbot opendkim opendkim-tools

# Get server IP address
SERVER_IP=$(hostname -I | awk '{print $1}')

# Get list of available hostnames
# HOSTNAMES=$(ls /etc/apache2/sites-available | sed -e 's/\.conf$//') 
# Prompt user to manually enter domain names pointing to this server
read -p "Please enter the domain names pointing to this server, separated by spaces: " -a HOSTNAMES

# Prompt user to point mail subdomains
echo "Please point mail.<hostname> for all domains on the server to this server IP: $SERVER_IP"
read -p "Ready to go? (yes/no): " ready

#if [[ "$ready" != "yes" ]]; then
#  echo "Exiting..."
#  exit 1
#fi

# Obtain certificates for mail subdomains
for domain in $HOSTNAMES; do
  sudo certbot certonly --standalone -d mail.$domain
done

# Create a renewal hook for certbot
echo "#!/bin/bash
systemctl reload postfix
systemctl reload dovecot
" | sudo tee /etc/letsencrypt/renewal-hooks/deploy/reload-services.sh
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-services.sh

# Configure Postfix
POSTFIX_MAIN_CF="/etc/postfix/main.cf"
sudo cp $POSTFIX_MAIN_CF ${POSTFIX_MAIN_CF}.bak

sudo bash -c "cat > $POSTFIX_MAIN_CF" <<EOL
smtpd_tls_security_level=may
smtp_tls_security_level=may
smtpd_tls_auth_only=yes

smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_auth_enable = yes
smtpd_tls_auth_only = yes
broken_sasl_auth_clients = yes
smtpd_recipient_restrictions = permit_sasl_authenticated, permit_mynetworks, reject_unauth_destination

smtpd_tls_loglevel = 1
smtpd_tls_received_header = yes
smtpd_tls_session_cache_timeout = 3600s
tls_random_source = dev:/dev/urandom

myhostname = mail.${HOSTNAMES[0]}
mydestination = localhost, \$(hostname)
virtual_alias_domains = $(echo $HOSTNAMES | tr ' ' ,)
virtual_alias_maps = hash:/etc/postfix/virtual
EOL

# Add TLS parameters for each domain
for domain in $HOSTNAMES; do
  sudo bash -c "cat >> $POSTFIX_MAIN_CF" <<EOL
smtpd_tls_cert_file=/etc/letsencrypt/live/mail.$domain/fullchain.pem
smtpd_tls_key_file=/etc/letsencrypt/live/mail.$domain/privkey.pem
EOL
done

# Generate the virtual map database
sudo postmap /etc/postfix/virtual
sudo systemctl restart postfix

# Configure Dovecot
DOVECOT_CONF="/etc/dovecot/conf.d/10-ssl.conf"
sudo cp $DOVECOT_CONF ${DOVECOT_CONF}.bak

sudo bash -c "cat > $DOVECOT_CONF" <<EOL
ssl = required
ssl_dh = </etc/dovecot/dh.pem
ssl_protocols = !SSLv3 !SSLv2
ssl_cipher_list = HIGH:!aNULL:!MD5
EOL

# Add SSL cert and key for each domain
for domain in $HOSTNAMES; do
  sudo bash -c "cat >> $DOVECOT_CONF" <<EOL
ssl_cert = </etc/letsencrypt/live/mail.$domain/fullchain.pem
ssl_key = </etc/letsencrypt/live/mail.$domain/privkey.pem
EOL
done

# Generate Diffie-Hellman parameter file
sudo openssl dhparam -out /etc/dovecot/dh.pem 4096

# Disable plain auth and configure mail location
sudo bash -c "cat >> /etc/dovecot/conf.d/10-auth.conf" <<EOL
disable_plaintext_auth = yes
auth_mechanisms = plain login
EOL

sudo bash -c "cat >> /etc/dovecot/conf.d/10-mail.conf" <<EOL
mail_location = maildir:~/Maildir
EOL

# Create users file for Dovecot
sudo touch /etc/dovecot/users

# Restart Dovecot
sudo systemctl restart dovecot

# Configure SpamAssassin
SPAMASSASSIN_CONF="/etc/spamassassin/local.cf"
sudo cp $SPAMASSASSIN_CONF ${SPAMASSASSIN_CONF}.bak

sudo bash -c "cat > $SPAMASSASSIN_CONF" <<EOL
# Enable Bayesian filtering
use_bayes 1
bayes_auto_learn 1

# Enable network tests
skip_rbl_checks 0
use_razor2 1
use_pyzor 1
use_dcc 1

# Set required score for spam
required_score 5.0

# Add more custom rules or configurations here if needed
EOL

# Enable and start SpamAssassin
sudo systemctl enable spamassassin
sudo systemctl start spamassassin

# Configure OpenDKIM
OPENDKIM_CONF="/etc/opendkim.conf"
sudo cp $OPENDKIM_CONF ${OPENDKIM_CONF}.bak

sudo bash -c "cat > $OPENDKIM_CONF" <<EOL
Syslog          yes
UMask           002
Socket          inet:12345@localhost
PidFile         /var/run/opendkim/opendkim.pid
Mode            sv
Canonicalization        relaxed/simple
Selector        default
KeyTable        /etc/opendkim/KeyTable
SigningTable    /etc/opendkim/SigningTable
ExternalIgnoreList      refile:/etc/opendkim/TrustedHosts
InternalHosts   refile:/etc/opendkim/TrustedHosts
EOL

# Create required files for OpenDKIM
sudo touch /etc/opendkim/KeyTable
sudo touch /etc/opendkim/SigningTable
sudo touch /etc/opendkim/TrustedHosts

# Generate DKIM keys and configure OpenDKIM
for domain in $HOSTNAMES; do
  sudo mkdir -p /etc/opendkim/keys/$domain
  sudo opendkim-genkey -s mail -d $domain -D /etc/opendkim/keys/$domain
  sudo chown -R opendkim:opendkim /etc/opendkim/keys/$domain
  sudo bash -c "cat >> /etc/opendkim/KeyTable" <<EOL
mail._domainkey.$domain $domain:mail:/etc/opendkim/keys/$domain/mail.private
EOL
  sudo bash -c "cat >> /etc/opendkim/SigningTable" <<EOL
*@${domain} mail._domainkey.${domain}
EOL
  sudo bash -c "cat >> /etc/opendkim/TrustedHosts" <<EOL
$domain
EOL
done

# Restart OpenDKIM and Postfix
sudo systemctl restart opendkim
sudo systemctl restart postfix

# Create DNS configuration guide
DNS_GUIDE="/var/www/html/emails-dns.txt"
echo "SPF, DKIM, DMARC configuration for each domain:" | sudo tee $DNS_GUIDE
for domain in $HOSTNAMES; do
  DKIM_KEY=$(sudo cat /etc/opendkim/keys/$domain/mail.txt)
  sudo bash -c "cat >> $DNS_GUIDE" <<EOL

Domain: $domain

SPF Record:
Type: TXT
Name: @
Value: v=spf1 mx a ip4:$SERVER_IP -all

DKIM Record:
Type: TXT
Name: mail._domainkey
Value: $(echo $DKIM_KEY | grep -o '"v=.*"' | tr -d '"')

DMARC Record:
Type: TXT
Name: _dmarc
Value: v=DMARC1; p=none; rua=mailto:dmarc-reports@$domain

EOL
done

echo "Configuration complete. Please refer to /var/www/html/emails-dns.txt for DNS records."

# Configure Fail2ban for Postfix and Dovecot
sudo bash -c "cat > /etc/fail2ban/jail.local" <<EOL
[postfix]
enabled  = true
port     = smtp,ssmtp
filter   = postfix
logpath  = /var/log/mail.log
maxretry = 5

[dovecot]
enabled  = true
port     = pop3,pop3s,imap,imaps
filter   = dovecot
logpath  = /var/log/mail.log
maxretry = 5
EOL

# Reload Fail2ban to apply changes
sudo systemctl restart fail2ban

echo "Fail2ban has been configured for Postfix and Dovecot."
