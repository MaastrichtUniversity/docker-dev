from irods.session import iRODSSession
from irods.access import iRODSAccess
from irods.exception import *
import configparser
import ldap
import string
import random
import smtplib
import sys

from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText


# Given an user's DN return the email address
def get_email_by_dn(dn, l):
    email = ''
    baseDN = dn
    searchScope = ldap.SCOPE_SUBTREE
    retrieveAttributes = ['mail']
    searchFilter = "(&(objectCategory=person)(objectClass=user))"

    # Perform the LDAP search
    id = l.search(baseDN, searchScope, searchFilter, retrieveAttributes)
    result_type, result = l.result(id, 0)
    if result:
        for dn, attrb in result:
            if 'mail' in attrb and attrb['mail']:
                email = attrb['mail'][0].lower()
                break
    return email


# Given an AD group name, return mail addresses of members.
def get_group_members(group_name, l, ):
    baseDN = ADBaseDN
    searchScope = ldap.SCOPE_SUBTREE
    retrieveAttributes = ['*']
    searchFilter = "(objectClass=*)"

    # Perform the LDAP search
    id = l.search(baseDN, searchScope, searchFilter, retrieveAttributes)

    result_type, result = l.result(id, 0)

    print(result)
    members = []
    if result:

        if len(result[0]) >= 2 and 'member' in result[0][1]:
            members_tmp = result[0][1]['member']
            for m in members_tmp:
                email = get_email_by_dn(m, l)
                if email:
                    members.append(email)
    return members


def send_welcome_email(fromAddress, toAddress, smtpServer, smtpPort):
    # Create message container - the correct MIME type is multipart/alternative.
    msg = MIMEMultipart('alternative')
    msg['Subject'] = "Welcome to DataHub"
    msg['From'] = "DataHub User Management"
    msg['To'] = toAddress

    # Create the body of the message (a plain-text and an HTML version).
    text = "A DataHub user account has been automatically created for you. This e-mail contains HTML formatting. Make " \
           "sure that you're using a HTML-compatible e-mail client to read the entire message of this e-mail."

    # HTML body stored in email_templates directory
    if "M4I" in iRODSgroup:
        with open("email_templates/m4i.html", "r") as myfile:
            html = myfile.read()
    else:
        with open("email_templates/default.html", "r") as myfile:
            html = myfile.read()

    # Modify the HTML-string to contain the actual username
    html = html.replace("PLACEHOLDER_USERNAME", toAddress)

    # Record the MIME types of both parts - text/plain and text/html.
    part1 = MIMEText(text, 'plain')
    part2 = MIMEText(html, 'html')

    # Attach parts into message container.
    # According to RFC 2046, the last part of a multipart message, in this case
    # the HTML message, is best and preferred.
    msg.attach(part1)
    msg.attach(part2)

    # Send the message via SMTP server.
    s = smtplib.SMTP(smtpServer, smtpPort)

    # sendmail function takes 3 arguments: sender's address, recipient's address
    # and message to send - here it is sent as one string.
    s.sendmail(fromAddress, toAddress, msg.as_string())
    s.quit()



# #################MAIN##################

# Config Parser
Config = configparser.ConfigParser()
if len(sys.argv) > 1:
    config = sys.argv[1]
else:
    config = 'config.ini'
Config.read(config)

# Options config
dryRun = Config.get('OPTIONS', 'dry_run')
sendEmail = Config.get('OPTIONS', 'send_email')

# AD config
ADUserName = Config.get('LDAP', 'ADUserName')
ADPassword = Config.get('LDAP', 'ADPassword')
ADgroup = Config.get('LDAP', 'ADgroup')
ADServer = Config.get('LDAP', 'ADServer')
ADBaseDN = Config.get('LDAP', 'ADBaseDN')

# iRODS config
iRODShost = Config.get('iRODS', 'host')
iRODSport = Config.get('iRODS', 'port')
iRODSuser = Config.get('iRODS', 'user')
iRODSpassword = Config.get('iRODS', 'password')
iRODSzone = Config.get('iRODS', 'zone')
iRODSgroup = Config.get('iRODS', 'group')

# E-mail config
fromAddress = Config.get('EMAIL', 'FROM_ADDR')
smtpServer = Config.get('EMAIL', 'SMTP_SERVER')
smtpPort = Config.get('EMAIL', 'SMTP_PORT')

if dryRun == "true":
    print("EXECUTING SCRIPT IN DRY MODE! No changes will be made to iCAT. No e-mails will be sent. \n")

# Setup AD connection
l = ldap.initialize(ADServer)
l.protocol_version = ldap.VERSION3
l.simple_bind_s(ADUserName, ADPassword)

# Setup iRODS connection
sess = iRODSSession(host=iRODShost, port=iRODSport, user=iRODSuser, password=iRODSpassword, zone=iRODSzone)

# Setup random passwords
# Just alphanumeric characters
chars = "foobar"
pwdSize = 20

# Get user in groups from AD
group_members = get_group_members(ADgroup, l)

# Loop over users
for userName in group_members:
    # Print username
    print(userName)

    user = None

    # Check if user exists
    existsUsername = True
    try:
        user = sess.users.get(userName)
    except UserDoesNotExist:
        existsUsername = False

    # If user does not exists create user
    if not existsUsername:
        try:
            if dryRun != "true":
                user = sess.users.create(userName, 'rodsuser')
                password = ''.join((random.choice(chars)) for x in range(pwdSize))
                sess.users.modify(userName, 'password', password)
            print("\t" + userName + " created")
            toAddress = userName
            # UNCOMMENT line below to override the user's e-mail address (for testing purposes)
            # toAddress = "m.coonen@maastrichtuniversity.nl"
            if dryRun != "true" and sendEmail == "true":
                send_welcome_email(fromAddress, toAddress, smtpServer, smtpPort)
            if sendEmail == "true":
                # Print debug statement regardless of dryRun option
                print("\tWelcome e-mail sent to " + toAddress)
        except:
            print("User creation error")
    else:
        print("\tUser already exists")

    group = None

    # Check if the group exists
    existsGroup = True
    try:
        group = sess.user_groups.get(iRODSgroup)
    except UserGroupDoesNotExist:
        existsGroup = False

    if not existsGroup:
        try:
            if dryRun != "true":
                group = sess.user_groups.create(iRODSgroup)
            print("\tGroup " + iRODSgroup + " created")
        except:
            print("Group Creation error")
    else:
        print("\tGroup already exists")

    # Add the user to the iRODSgroup defined in config file
    try:
        if dryRun != "true":
            group.addmember(user.name)
            print("\t" + userName + " added to group " + iRODSgroup)
    except CATALOG_ALREADY_HAS_ITEM_BY_THAT_NAME:
        print("\tUser already in group " + iRODSgroup)
    except:
        print("could not add user to group " + iRODSgroup)

    # Add the user to the group DH-ingest (= ensures that user is able to create and ingest dropzones)
    try:
        if dryRun != "true":
            ingestGroup = sess.user_groups.get("DH-ingest")
            ingestGroup.addmember(user.name)
            print("\t" + userName + " added to group DH-ingest")
    except CATALOG_ALREADY_HAS_ITEM_BY_THAT_NAME:
        print("\tUser already in group DH-ingest")
    except:
        print("could not add user to group DH-ingest")