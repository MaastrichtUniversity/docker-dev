from irods.session import iRODSSession
from irods.access import iRODSAccess
from irods.exception import *
import configparser
import ldap
import string
import random
import smtplib
import sys
from enum import Enum

from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText



class UserAVU(Enum):
    """Enum user AVU
    """
    DISPLAY_NAME = 'display-name'
    EMAIL = "email"


HANDLED_AVU_KEYS = ['xx', 'test', UserAVU.DISPLAY_NAME.value, UserAVU.EMAIL.value]


##########################################################
def simple_query_test(l):
    baseDN = "dc=datahubmaastricht,dc=nl" #ADBaseDN
    baseDN = "ou=users,dc=datahubmaastricht,dc=nl" #ldap.NO_SUCH_OBJECT: {'desc': 'No such object', 'matched': 'ou=users,dc=datahubmaastricht,dc=nl'}

    searchScope = ldap.SCOPE_SUBTREE
    retrieveAttributes = ['*']  # all=*, ['uid', 'mail', 'cn', 'displayName']
    searchFilter = "(objectClass=*)"

    # Perform the LDAP search
    id = l.search(baseDN, searchScope, searchFilter, retrieveAttributes)
    result_type, result = l.result(id, all=1)
    print( "simple_query_test search result: "+ str(result) )


##########################################################
#get all the relevant attributes of all users in LDAP, returns an array with dictionaries
def get_users_from_ldap(l):
    ldap_users = []

    baseDN = ADBaseDN
    searchScope = ldap.SCOPE_SUBTREE
    retrieveAttributes = ['uid', 'mail', 'cn', 'displayName']  # all=*
    searchFilter = "(objectClass=*)"

    # Perform the LDAP search
    id = l.search(baseDN, searchScope, searchFilter, retrieveAttributes)
    #all = 1
    # If all is 0, search entries will be returned one at a time as they come in, via separate calls to result().
    # If all is 1, the search response will be returned in its entirety, i.e. after all entries and the final search result have been received.

    result_type, result = l.result(id, all=0)
    while result:
        #print( "get_users_from_ldap search result: "+ str(result) )

        if result[0] and len( result[0] ) == 2:
            entry= result[0][1]
            if entry:
                #print( entry )
                uid = entry.get(  'uid', [b""])[0].decode("utf-8").strip()
                mail = entry.get( 'mail', [b""])[0].decode("utf-8").strip()
                cn = entry.get('cn', [b""])[0].decode("utf-8").strip()
                #display name is an attribute
                displayName = entry.get('displayName', [b""])[0].decode("utf-8").strip()

                user = {"uid": uid, "mail": mail, "cn": cn, "displayName": displayName }
                ldap_users.append( user )
        result_type, result = l.result(id, all=0)

    return ldap_users



##########################################################
#change the attributes to a user class/dictionary
def create_new_irods_user( irodsSession, user ):
    print("--\t\tcreate new irods user:" )
    print( "\t\tuser-data:" + str(user) )
    irodsUser = irodsSession.users.create( user['uid'], 'rodsuser')
    #add AVUs	 
    irodsUser.metadata.add(UserAVU.EMAIL.value, user['mail'])
    irodsUser.metadata.add(UserAVU.DISPLAY_NAME.value, user['displayName'])
    #add password
    password = ''.join((random.choice(chars)) for x in range(pwdSize))
    irodsSession.users.modify(user['uid'], 'password', password)
    print("--\t\tcreate new irods user DONE")
    return irodsUser

##########################################################

def get_all_AVUs( irodsUser ):    
    existingAVUs = {}
    for item in irodsUser.metadata.items():
       existingAVUs[ item.name ] = item.value   
    return existingAVUs
    
##########################################################

def remove_all_AVUs( irodsUser ):
   #keys_to_be_removed = ['email', 'display-name']	
   #remove all existing AVUs (actually should check if in list of removable AVUs):
	for item in irodsUser.metadata.items():
		key, value = item.name, item.value
		#if key in HANDLED_AVU_KEYS:
		irodsUser.metadata.remove( key, value )
	 	  

##########################################################
	 	  
def set_singular_AVU( irodsUser, existingAVUs, AVUkey, AVUvalue ):
	#print( "--- set a singular AVU")
	if not AVUkey in HANDLED_AVU_KEYS:
			print( "the key is not in the list of changeable attributes:" + AVUkey + " " + str(HANDLED_AVU_KEYS) )
			return
	#print( existingAVUs.items())
	AVU_exists = False
	for item in existingAVUs.items():
		key, value = item
		#print( "  --> " + key + " " + value )
		if key == AVUkey and value != AVUvalue:
			#print( "  --> removing " + key + " " + value )
			irodsUser.metadata.remove( key, value )
		if key == AVUkey and value == AVUvalue:
			#print( "AVU already exists, no changes")
			AVU_exists = True
  
	if AVUvalue and not AVU_exists:
		#print( "create new AVU")
		irodsUser.metadata.add( AVUkey, AVUvalue )
    
    
    
##########################################################
#change the attributes to a user class/dictionary
def sync_existing_irods_user( irodsSession, irodsUser, user ):
	print("--\t\tchanging irods user:" + user['uid'] )
	print( "\t\tuser-data:" + str(user) )
	
	try:
		#remove_all_AVUs( irodsUser )
		#read current AVUs and change if needed
		existingAVUs = get_all_AVUs( irodsUser )
		print( "\t\texisting AVUs BEFORE: " + str(existingAVUs) )
		#careful: because the list of existing AVUs is not updated changing a key multiple times will lead to strange behavior! 
		set_singular_AVU( irodsUser, existingAVUs, 'test', 'some new value' )
		set_singular_AVU( irodsUser, existingAVUs, UserAVU.EMAIL.value, user['mail'] )
		set_singular_AVU( irodsUser, existingAVUs, UserAVU.DISPLAY_NAME.value, user['displayName'] )
	
	except iRODSException as error:
		print( "error:" + str(error) )
		
	existingAVUs = get_all_AVUs( irodsUser )
	print( "\t\texisting AVUs AFTER: " + str(existingAVUs) )
	print( "--\t\tupdating existing irods user DONE." )
	return irodsUser
   
   
##########################################################
def remove_oboslete_irods_users():
	

##########################################################
#get a mapping of groups to users   
def get_ldap_groups_and_uuid( l ):
    # NEEDS FIX A: implement me
    pass	



##########################################################
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

#simple test
#simple_query_test( l )


# Setup iRODS connection
sess = iRODSSession(host=iRODShost, port=iRODSport, user=iRODSuser, password=iRODSpassword, zone=iRODSzone)

# Setup random passwords
# Just alphanumeric characters
chars = "foobar"
pwdSize = 20

# Get user in groups from AD
print( "getting list of users from LDAP" )
ldap_users = get_users_from_ldap(l)
print( "LDAP users found: " + len(ldap_users) )
#group_members = get_group_members(ADgroup, l)

# Loop over users
for user in ldap_users:
    # Print username
    print( "\tsyncing LDAP user: " + user['uid'] )
    uid = user['uid']
    irodUser = None

    # Check if user exists
    existsUsername = True
    try:
        print("\tcheck if exists...")
        irodsUser = sess.users.get(uid)
        print("\texists")
    except UserDoesNotExist:
        existsUsername = False
        print("\tdoesnt exist")

    # If user does not exists create user
    if not existsUsername:
        try:
            if dryRun != "true":
            	 create_new_irods_user( sess, user )
            print("\t" + user['uuid'] + " created")
            toAddress =  user['mail']
            # UNCOMMENT line below to override the user's e-mail address (for testing purposes)
            # toAddress = "m.coonen@maastrichtuniversity.nl"
            if dryRun != "true" and sendEmail == "true":
                send_welcome_email(fromAddress, toAddress, smtpServer, smtpPort)
            if sendEmail == "true":
                # Print debug statement regardless of dryRun option
                print("\tWelcome e-mail sent to " + toAddress)
        except Exception as e:
            print("\tUser creation error")
            print( e )
    else:
        print("\tUser already exists")
        sync_existing_irods_user( sess, irodsUser, user )
    
    #break

#    group = None
#
#    # Check if the group exists
#    existsGroup = True
#    try:
#        group = sess.user_groups.get(iRODSgroup)
#    except UserGroupDoesNotExist:
#        existsGroup = False#
#
#    if not existsGroup:
#        try:
#            if dryRun != "true":
#                group = sess.user_groups.create(iRODSgroup)
#            print("\tGroup " + iRODSgroup + " created")
#        except:
#            print("Group Creation error")
#    else:
#        print("\tGroup already exists")
#
#    # Add the user to the iRODSgroup defined in config file
#    try:
#        if dryRun != "true":
#            group.addmember(user.name)
#            print("\t" + userName + " added to group " + iRODSgroup)
#    except CATALOG_ALREADY_HAS_ITEM_BY_THAT_NAME:
#        print("\tUser already in group " + iRODSgroup)
#    except:
#        print("could not add user to group " + iRODSgroup)

    # Add the user to the group DH-ingest (= ensures that user is able to create and ingest dropzones)
    try:
        if dryRun != "true":
            ingestGroup = sess.user_groups.get("DH-ingest")
            ingestGroup.addmember(user['uid'])
            print("\t" + userName + " added to group DH-ingest")
    except CATALOG_ALREADY_HAS_ITEM_BY_THAT_NAME:
        print("\tUser already in group DH-ingest")
    except:
        print("could not add user to group DH-ingest")
    print( "------")