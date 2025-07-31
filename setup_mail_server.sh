#!/bin/bash

# Update and install required packages
sudo apt update
sudo apt install -y postfix dovecot-core dovecot-imapd dovecot-auth spamassassin fail2ban certbot opendkim opendkim-tools

# Get server IP address
SERVER_IP=$(hostname -I | awk '{print $1}')

# Get list of available hostnames
# HOSTNAMES=$(ls /etc/apache2/sites-available | sed -e 's/\.conf$//') 
# Prompt user to manually enter domain names pointing to this server
read -p "Please enter the domain names pointing to this server, separated by spaces: " -a HOSTNAMES

# Prompt user to point mail subdomains
echo "Please point mail.<hostname> for all domains on the server to this server IP: $SERVER_IP"
read -p "Ready to go? (yes/no): " ready

if [[ "$ready" != "yes" ]]; then
  echo "Exiting..."
  exit 1
fi


# Stop Apache or Nginx before running Certbot to avoid port conflicts
# sudo systemctl stop apache2 

# Obtain certificates for mail subdomains
for domain in $HOSTNAMES; do
  sudo certbot certonly --standalone -d mail.$domain
  if [[ $? -ne 0 ]]; then
    echo "Failed to obtain certificate for mail.$domain. Please check the logs."
    # Handle error: You can choose to exit or continue depending on your preference
    exit 1
  fi
done

# Restart Apache or Nginx after obtaining certificates
sudo systemctl start apache2

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
mydestination = localhost
virtual_mailbox_domains = $(echo $HOSTNAMES | tr ' ' ,)
virtual_mailbox_maps = hash:/etc/postfix/vmailbox
virtual_mailbox_base = /var/mail/vhosts
virtual_minimum_uid = 1000
virtual_uid_maps = static:5000
virtual_gid_maps = static:5000
virtual_alias_maps = hash:/etc/postfix/virtual
EOL

# Add TLS parameters for each domain
for domain in $HOSTNAMES; do
  sudo bash -c "cat >> $POSTFIX_MAIN_CF" <<EOL
smtpd_tls_cert_file=/etc/letsencrypt/live/mail.$domain/fullchain.pem
smtpd_tls_key_file=/etc/letsencrypt/live/mail.$domain/privkey.pem
EOL
done

# Create virtual mail user and directories
sudo groupadd -g 5000 vmail 2>/dev/null || true
sudo useradd -g vmail -u 5000 vmail -d /var/mail/vhosts -s /sbin/nologin 2>/dev/null || true
sudo mkdir -p /var/mail/vhosts
sudo chown -R vmail:vmail /var/mail/vhosts
sudo chmod -R 755 /var/mail/vhosts

# Create virtual mailbox and alias files
sudo touch /etc/postfix/vmailbox
sudo touch /etc/postfix/virtual

# Create directory structure for each domain
for domain in $HOSTNAMES; do
  sudo mkdir -p /var/mail/vhosts/$domain
  sudo chown -R vmail:vmail /var/mail/vhosts/$domain
done

# Generate the virtual map databases
sudo postmap /etc/postfix/vmailbox
sudo postmap /etc/postfix/virtual

# Configure Postfix master.cf for SASL submission
POSTFIX_MASTER_CF="/etc/postfix/master.cf"
sudo cp $POSTFIX_MASTER_CF ${POSTFIX_MASTER_CF}.bak

# Add submission port configuration for SASL authentication
sudo bash -c "cat >> $POSTFIX_MASTER_CF" <<EOL
submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_tls_auth_only=yes
  -o smtpd_reject_unlisted_recipient=no
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o smtpd_helo_restrictions=permit_sasl_authenticated,reject
  -o smtpd_sender_restrictions=permit_sasl_authenticated,reject
  -o smtpd_recipient_restrictions=permit_sasl_authenticated,reject_unauth_destination
  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING
EOL

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

# Configure Dovecot for virtual users
sudo bash -c "cat >> /etc/dovecot/conf.d/10-auth.conf" <<EOL
disable_plaintext_auth = yes
auth_mechanisms = plain login
passdb {
  driver = passwd-file
  args = scheme=BLF-CRYPT username_format=%u /etc/dovecot/users
}
userdb {
  driver = static
  args = uid=vmail gid=vmail home=/var/mail/vhosts/%d/%n
}
EOL

sudo bash -c "cat >> /etc/dovecot/conf.d/10-mail.conf" <<EOL
mail_location = maildir:/var/mail/vhosts/%d/%n/Maildir
mail_uid = vmail
mail_gid = vmail
first_valid_uid = 5000
last_valid_uid = 5000
EOL

# Configure Dovecot master service for Postfix SASL authentication
DOVECOT_MASTER_CONF="/etc/dovecot/conf.d/10-master.conf"
sudo cp $DOVECOT_MASTER_CONF ${DOVECOT_MASTER_CONF}.bak 2>/dev/null || true

sudo bash -c "cat >> $DOVECOT_MASTER_CONF" <<EOL
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
}
EOL

# Create users file for Dovecot virtual users with restricted permissions
sudo touch /etc/dovecot/users
sudo chmod 600 /etc/dovecot/users
sudo chown root:dovecot /etc/dovecot/users

# Function to add virtual mail users
add_mail_user() {
    read -p "Enter email address (user@domain.com): " email
    read -s -p "Enter password: " password
    echo
    
    # Extract domain from email
    domain=$(echo "$email" | cut -d'@' -f2)
    username=$(echo "$email" | cut -d'@' -f1)
    
    # Check if domain is configured
    if [[ ! " ${HOSTNAMES[@]} " =~ " ${domain} " ]]; then
        echo "Warning: Domain $domain is not in the configured domains list."
        read -p "Continue anyway? (yes/no): " continue_anyway
        if [[ "$continue_anyway" != "yes" ]]; then
            echo "User creation cancelled."
            return
        fi
    fi
    
    # Generate password hash using BLF-CRYPT
    password_hash=$(doveadm pw -s BLF-CRYPT -p "$password")
    
    # Add user to Dovecot users file
    echo "$email:$password_hash::::" | sudo tee -a /etc/dovecot/users > /dev/null
    
    # Add user to Postfix virtual mailbox file
    echo "$email $domain/$username/" | sudo tee -a /etc/postfix/vmailbox > /dev/null
    
    # Create user directory structure
    sudo mkdir -p "/var/mail/vhosts/$domain/$username/Maildir/{cur,new,tmp}"
    sudo chown -R vmail:vmail "/var/mail/vhosts/$domain/$username"
    sudo chmod -R 700 "/var/mail/vhosts/$domain/$username"
    
    # Rebuild postfix maps
    sudo postmap /etc/postfix/vmailbox
    
    echo "Virtual mail user $email added successfully"
    echo "Mailbox location: /var/mail/vhosts/$domain/$username/Maildir"
}

# Prompt to add initial virtual mail user
echo "Would you like to add a virtual mail user now? (recommended)"
echo "Users will be in format: user@domain.com"
read -p "Add user? (yes/no): " add_user
if [[ "$add_user" == "yes" ]]; then
    add_mail_user
    echo "You can add more virtual users later by running the add_mail_user function"
    echo "Or manually add to /etc/dovecot/users and /etc/postfix/vmailbox"
fi

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
echo ""
echo "VIRTUAL MAIL SERVER SETUP COMPLETE!"
echo "Your mail server is now configured with true virtual users and SASL authentication."
echo ""
echo "Mail Client Settings:"
echo "- SMTP Server: mail.${HOSTNAMES[0]}"
echo "- SMTP Port: 587 (submission with STARTTLS)"
echo "- IMAP Server: mail.${HOSTNAMES[0]}"
echo "- IMAP Port: 993 (IMAPS)"
echo "- Authentication: Required for both SMTP and IMAP"
echo "- Username: Full email address (user@domain.com)"
echo ""
echo "Virtual User Management:"
echo "- All mailboxes stored in: /var/mail/vhosts/"
echo "- Virtual mail user: vmail (UID/GID 5000)"
echo "- No system users required for email accounts"
echo ""
echo "To add more virtual users later:"
echo "1. Generate password hash: doveadm pw -s BLF-CRYPT -p 'password'"
echo "2. Add to /etc/dovecot/users: email@domain.com:hash::::"
echo "3. Add to /etc/postfix/vmailbox: email@domain.com domain.com/username/"
echo "4. Run: sudo postmap /etc/postfix/vmailbox"
echo "5. Create maildir: sudo mkdir -p /var/mail/vhosts/domain.com/username/Maildir/{cur,new,tmp}"
echo "6. Set ownership: sudo chown -R vmail:vmail /var/mail/vhosts/domain.com/username"
echo ""

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
