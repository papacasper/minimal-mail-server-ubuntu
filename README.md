# minimal-mail-server-ubuntu
A minimal mail server setup for Ubuntu system. Use it on cloud or VPS droplets or machines. Good for developers, tech-savvy people, and nerds.


**Minimal Mail Server Ubuntu** is a minimal setup (yet with easy guidance) script designed to configure a secure and functional mail server on an Ubuntu 20.04+ droplet. This script automates the installation and configuration of essential mail server components, including Postfix, Dovecot, SpamAssassin, Fail2ban, Certbot, and OpenDKIM, to provide a complete mail solution for multiple domains. 

**What does it not cover? and why?**
- This script had to be minimal for our use case. We didn't need Calendar, Contacts, ActiveSync stuff, as well as webmail (a frontend view of emails). To avoid loading server (a cloud droplet on Ubuntu) with unnecessary stuff at that moment, we scripted it. 

## Features

- **Postfix**: Configured for SMTP with SSL/TLS support and submission port (587) with SASL authentication.
- **Dovecot**: Set up for IMAP with secure authentication and virtual user support.
- **SpamAssassin**: Integrated for effective spam filtering.
- **Fail2ban**: Enhanced security with intrusion protection.
- **Certbot**: Automated SSL certificate management for mail server domains.
- **OpenDKIM**: DKIM signing for email authenticity and integrity.
- **Virtual Users**: True virtual user system with dedicated vmail user (no system users required).
- **SASL Authentication**: Secure SMTP authentication for email submission.
- **User Management**: Comprehensive script for adding, removing, and managing mail users.

## Key Benefits
- **Automated Setup:** Easily configure your mail server with a single script.
- **Secure Communication:** Enforces SSL/TLS encryption for email transmission.
- **Spam Protection:** Incorporates advanced spam filtering mechanisms.
- **Dynamic Configuration:** Automatically handles multiple domains with individual configurations.
- **DNS Configuration Guide:** Generates detailed DNS records for SPF, DKIM, and DMARC.
- **Virtual User Management:** Secure, scalable user system independent of system accounts.
- **SASL Authentication:** Proper authenticated SMTP submission on port 587.
- **Easy User Management:** Intuitive script for managing email accounts with validation and safety features.

## Recent Updates

We have recently made significant updates to enhance the functionality of the mail server:

1. **Virtual User Support**: Transitioned to a true virtual user system which separates mail users from system users, offering improved security and management.
2. **SASL Authentication**: Implemented and fine-tuned SASL authentication for secure email transmission and reception.
3. **User Management Script**: Added a comprehensive script for managing mail users providing capabilities to add, remove, and change user passwords efficiently.

## Important Setup Instructions

Before running the script, ensure you have configured DNS settings for your domains:

1. **Point 'mail' CNAME**: Ensure that `mail.yourdomain.com` (replace `yourdomain.com` with your actual domain) is pointing to your server's IP address. If you have multiple domains or subdomains, ensure that the `mail` CNAME is correctly set for all of them.

2. **TLD or Parent Domain**: Alternatively, if your top-level domain (TLD) or parent domain points to this server, make sure it is correctly configured as well.

## Installation

To install and configure your mail server, run the following command:

```bash
wget https://raw.githubusercontent.com/digitalsetups/minimal-mail-server-ubuntu/main/setup_mail_server.sh
```
```
chmod +x setup_mail_server.sh
```
```
./setup_mail_server.sh
```

Follow with the prompts after it. 
 
## After Installation

- After running the script, you will receive a guide with DNS configuration details for SPF, DKIM, and DMARC records. Make sure to update your DNS records accordingly to ensure proper email delivery and authentication.
- **Locate the Users File to create emails and passwords**: The users file for Dovecot is typically located at ```/etc/dovecot/users```. You can open this file with a text editor as ```sudo nano /etc/dovecot/users```. Open it after having user names and passwords from next steps.
- **Generate a Hashed Password for the email account**: You can generate a hashed password using the doveadm command: ```doveadm pw -s BLF-CRYPT```
- **Add New Email Users:** To add new email users, follow the format: ```user@example.com:{generated_pass_by_password_generation_command)``` - One email & pass per line. You can add users for all available hosts on the server.
- Send a test email

## Troubleshoot
- **Check Mail Server Status:** Ensure that all mail server services are running by executing:
  ```sudo systemctl status postfix```
  ```sudo systemctl status dovecot```
  ```sudo systemctl status spamassassin```
- **Review Logs in case of issue:** Check the logs for any errors or issues:

  ```sudo tail -f /var/log/mail.log```
  ```sudo tail -f /var/log/mail.err```

## Developed By

This script was developed by **[Aqsa J.](https://digitalsetups.org)** from **[Digital Setups](https://digitalsetups.org)** for her client's project. 

## Contributing

Feel free to fork the repository, submit issues, or contribute improvements via pull requests.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

[Back to Top](#minimal-mail-server-ubuntu)
[See the LICENSE file](LICENSE)
