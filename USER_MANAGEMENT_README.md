# Virtual Mail User Management Script

This script provides comprehensive management for virtual mail users in your Postfix + Dovecot mail server setup.

## Installation

1. Copy the script to your server:
```bash
chmod +x manage_mail_users.sh
```

2. Ensure the script has the correct paths configured (it should work with the main setup script automatically).

## Usage

### Command Line Mode

#### Add a user
```bash
# Interactive mode
./manage_mail_users.sh add

# With email only (will prompt for password)
./manage_mail_users.sh add user@example.com

# With email and password
./manage_mail_users.sh add user@example.com mypassword
```

#### Remove a user
```bash
# Interactive mode
./manage_mail_users.sh remove

# Direct removal
./manage_mail_users.sh remove user@example.com
```

#### Change password
```bash
# Interactive mode
./manage_mail_users.sh password

# With email only (will prompt for new password)
./manage_mail_users.sh password user@example.com

# With email and new password
./manage_mail_users.sh password user@example.com newpassword
```

#### List users
```bash
./manage_mail_users.sh list
```

#### Help
```bash
./manage_mail_users.sh help
```

### Interactive Mode

Run without arguments for an interactive menu:
```bash
./manage_mail_users.sh
```

## Features

### ✅ **User Management**
- **Add users**: Creates virtual mail users with proper directory structure
- **Remove users**: Safely removes users and all their data
- **Change passwords**: Updates user passwords with secure hashing
- **List users**: Shows all users with status information

### ✅ **Security Features**
- **Email validation**: Validates email format before processing
- **Domain validation**: Checks against configured domains
- **Password confirmation**: Double-checks passwords in interactive mode
- **Secure hashing**: Uses BLF-CRYPT for password storage
- **Privilege checking**: Ensures proper sudo/root access

### ✅ **Safety Features**
- **Existence checks**: Verifies users exist before operations
- **Confirmation prompts**: Asks for confirmation before destructive operations
- **Error handling**: Comprehensive error checking and reporting
- **Service reloading**: Automatically reloads Postfix and Dovecot after changes

### ✅ **User Experience**
- **Colored output**: Easy-to-read success/error/warning messages
- **Interactive menu**: User-friendly menu system
- **Command line support**: Can be used in scripts or manually
- **Detailed feedback**: Shows what's happening during operations

## File Locations

The script manages these files:
- **Dovecot users**: `/etc/dovecot/users`
- **Postfix virtual mailbox**: `/etc/postfix/vmailbox`
- **Postfix virtual aliases**: `/etc/postfix/virtual`
- **Mail directories**: `/var/mail/vhosts/domain.com/username/`

## Directory Structure

```
/var/mail/vhosts/
├── domain1.com/
│   ├── user1/
│   │   └── Maildir/
│   │       ├── cur/
│   │       ├── new/
│   │       └── tmp/
│   └── user2/
└── domain2.com/
    └── admin/
```

## Requirements

- Root or sudo access
- `doveadm` command available (installed with dovecot-auth)
- Postfix and Dovecot properly configured
- Virtual mail system set up (as per main setup script)

## Examples

### Add a user interactively
```bash
$ ./manage_mail_users.sh add
Enter email address (user@domain.com): john@example.com
Enter password for john@example.com: 
Confirm password: 
ℹ Info: Creating virtual mail user: john@example.com
✓ Virtual mail user john@example.com added successfully
ℹ Info: Mailbox location: /var/mail/vhosts/example.com/john/Maildir
```

### List all users
```bash
$ ./manage_mail_users.sh list
ℹ Info: Virtual Mail Users:
====================
admin@example.com - ✓ Active
user@example.com - ✓ Active
test@example.com - ✗ Missing Mailbox
====================
ℹ Info: Total users: 3
```

### Change password
```bash
$ ./manage_mail_users.sh password admin@example.com
Enter new password for admin@example.com: 
Confirm new password: 
ℹ Info: Changing password for: admin@example.com
✓ Password changed successfully for admin@example.com
```

## Troubleshooting

### Common Issues

1. **Permission denied**: Make sure you run with sudo or as root
2. **doveadm not found**: Install `dovecot-auth` package
3. **User not found**: Check if user exists with `list` command
4. **Domain validation warning**: Either add domain to server or continue anyway

### Log Files

Check these logs for mail server issues:
- `/var/log/mail.log` - Main mail log
- `/var/log/dovecot.log` - Dovecot specific log
- `journalctl -u postfix` - Postfix service log
- `journalctl -u dovecot` - Dovecot service log

## Integration

This script is designed to work seamlessly with the main mail server setup script. All paths and configurations are automatically compatible.

For automated user management, you can call this script from other scripts or cronjobs:

```bash
# Add user from script
./manage_mail_users.sh add newuser@domain.com secure_password

# Change password from script  
./manage_mail_users.sh password user@domain.com new_secure_password
```
