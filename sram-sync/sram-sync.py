from irods.session import iRODSSession
from irods.access import iRODSAccess
from irods.column import Criterion
from irods.models import User, UserGroup
from irods.exception import *

import configparser
import ldap
import string
import random
import smtplib
import sys
import time

from enum import Enum
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText


class UserAVU(Enum):
    """Enum user AVU
    """
    DISPLAY_NAME = 'display-name'
    EMAIL = "email"

##########################################################
class mUser:
	LDAP_ATTRIBUTES = ['uid', 'mail', 'cn', 'displayName']  # all=*
	AVU_KEYS = ['test', UserAVU.DISPLAY_NAME.value, UserAVU.EMAIL.value]

	def __init__(self, uid, displayName, email):
		self.uid = uid
		self.displayName = displayName
		self.email = email


##########################################################
def create_new_irods_user_password():
	if developMode:
		return 'foobar'
		
	# Setup random passwords
	# Just alphanumeric characters
	chars = "abcdefghijklmnopqrstuvw"
	pwdSize = 20
	return   ''.join((random.choice(chars)) for x in range(pwdSize))
  
  
##########################################################
def read_ldap_attribute(ldap_entry, key):
	return ldap_entry.get(  key, [b""])[0].decode("utf-8").strip()
	
def get_user_from_ldap( ldap_entry ):
	uid = read_ldap_attribute( ldap_entry, 'uid' )
	mail= read_ldap_attribute( ldap_entry, 'mail' )
	cn = read_ldap_attribute( ldap_entry, 'cn' )
	displayName = read_ldap_attribute( ldap_entry, 'displayName' )
	#user = {"uid": uid, "mail": mail, "cn": cn, "displayName": displayName }
	return mUser( uid, displayName, mail )

##########################################################
#get all the relevant attributes of all users in LDAP, returns an array with dictionaries
def get_users_from_ldap(l):
    ldap_users = []
    searchScope = ldap.SCOPE_SUBTREE
    retrieveAttributes = mUser.LDAP_ATTRIBUTES
    searchFilter = "(objectClass=*)"

    # Perform the LDAP search
    id = l.search(LDAPBaseDN, searchScope, searchFilter, retrieveAttributes)
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
                user = get_user_from_ldap(entry)
                ldap_users.append( user )
        result_type, result = l.result(id, all=0)

    return ldap_users


##########################################################
def create_new_irods_user( irodsSession, user ):
	if dryRun == "true":
	 	return
	log( 1, "--\t\tcreate a new irods user: %s" % user.uid )
	irodsUser = irodsSession.users.create( user.uid, 'rodsuser')
	#add AVUs	 
	irodsUser.metadata.add( UserAVU.EMAIL.value, user.email )
	irodsUser.metadata.add( UserAVU.DISPLAY_NAME.value, user.displayName )
	#add password
	password = create_new_irods_user_password() 
	irodsSession.users.modify(user.uid, 'password', password)
	return irodsUser

##########################################################
def get_all_AVUs( irodsUser ):    
    existingAVUs = {}
    for item in irodsUser.metadata.items():
       existingAVUs[ item.name ] = item.value   
    return existingAVUs
    
##########################################################
def remove_all_AVUs( irodsUser ):
   #remove all existing AVUs (actually should check if in list of removable AVUs):
	for item in irodsUser.metadata.items():
		key, value = item.name, item.value
		if key in mUser.AVU_KEYS:
			irodsUser.metadata.remove( key, value )
	 	  
##########################################################
	 	  
def set_singular_AVU( irodsUser, existingAVUs, AVUkey, AVUvalue ):
	#print( "--- set a singular AVU")
	if dryRun == "true":
		return
	if not AVUkey in mUser.AVU_KEYS:
			log( 1, "/tthe key is not in the list of changeable attributes:" + AVUkey + " " + str(mUser.AVU_KEYS) )
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
#
def sync_existing_irods_user( irodsSession, irodsUser, user ):
	log( 1, "--\t\tchanging existing irods user:" + user.uid )
	
	try:
		#remove_all_AVUs( irodsUser )
		#read current AVUs and change if needed
		existingAVUs = get_all_AVUs( irodsUser )
		log( 2, "\t\texisting AVUs BEFORE: " + str(existingAVUs) )
		#careful: because the list of existing AVUs is not updated changing a key multiple times will lead to strange behavior! 
		set_singular_AVU( irodsUser, existingAVUs, 'test', 'some new value' )
		set_singular_AVU( irodsUser, existingAVUs, UserAVU.EMAIL.value, user.email )
		set_singular_AVU( irodsUser, existingAVUs, UserAVU.DISPLAY_NAME.value, user.displayName )
	
	except iRODSException as error:
		log( 0, "error:" + str(error) )
		
	existingAVUs = get_all_AVUs( irodsUser )
	log( 2, "\t\texisting AVUs AFTER: " + str(existingAVUs) )
	return irodsUser
   
   
##########################################################
def syncable_irods_users( sess, unsyncedUsers ):
	#query = sess.query(User)
	#result = query.all()
	#print( result )
	#print( type( result.rows  ) )
	#print( type( result.rows[0]  ) )
	
	irodsUserNamesSet = set()
	#filter only rodsusers, filter the special users, check wich one are not in the LDAP list
	query = sess.query(User.name, User.id, User.type ).filter( 
     Criterion('=', User.type, 'rodsuser') )
	for result in query:
		if not result[ User.name ] in unsyncedUsers:
			irodsUserNamesSet.add( result[ User.name] )
	
	return irodsUserNamesSet

##########################################################
#get a mapping of groups to users   
def get_ldap_groups_and_uuid( l ):
    # NEEDS FIX A: implement me
    group2users = { "nanoscopy": ["p.vanschayck", "g.tria", "rbg.ravelli"],
    	"rit-l": ["p.vanschayck", "m.coonen", "d.theunissen", "p.suppers", "delnoy", "r.niesten", "r.brecheisen", "jonathan.melius", "k.heinen", "s.nijhuis" ],
      "DH-project-admins": [],
      "UM-SCANNEXUS" : [],
      "DH-ingest" : []
    } 
    return group2users
   
  
##########################################################  
def provide_group( sess, groupName ):
	group = None
	# Check if the group exists
	existsGroup = True
	try:
		group = sess.user_groups.get( groupName )
	except UserGroupDoesNotExist:
		existsGroup = False

	if not existsGroup:
		try:
			if dryRun != "true":
				group = sess.user_groups.create( groupName )
				log( 1, "\tGroup %s created" %  groupName )
		except:
			log( 0, "Group %s Creation error" % groupName )
	else:
		log( 1,"\tGroup %s already exists" % groupName )


########################################################## 
def add_user_to_group( sess, groupName, userName ):
	group = sess.user_groups.get( groupName )
	try:
		if dryRun != "true":
			group.addmember(userName)
			log( 1, "\t" + userName + " added to group " + groupName )
	except CATALOG_ALREADY_HAS_ITEM_BY_THAT_NAME:
		log( 2, "\tUser already in group " + groupName )
	except Exception as e:
		log( 1, "could not add user %s to group %s %s" % (userName, groupName, e) )


##########################################################
def remove_unused_metadata(session):
    from irods.message import GeneralAdminRequest
    from irods.api_number import api_number
    message_body = GeneralAdminRequest( 'rm', 'unusedAVUs', '','','','')
    req = iRODSMessage("RODS_API_REQ", msg = message_body,int_info=api_number['GENERAL_ADMIN_AN'])
    with session.pool.get_connection() as conn:
        conn.send(req)
        response=conn.recv()
        if (response.int_info != 0): raise RuntimeError("Error removing unused AVUs")


##########################################################
def remove_obsolete_irods_users( sess, ldap_users, irods_users ):
	deletion_candidates = irods_users.copy()
	for ldap_user in ldap_users:
		deletion_candidates.discard( ldap_user.uid )
	log( 0, "\twill delete %d irods users" % len(deletion_candidates) )
	#print( deletion_candidates )	
	for uid in deletion_candidates:
		user = sess.users.get( uid )
		log( 1, "\t\twill delete user %s" % uid )
		if dryRun != "true":
			#how to remove user from groups?
			#group.removemember(user.name)
			remove_all_AVUs( user )
			user.remove()
	#remove_unused_metadata( sess )

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


##########################################################

def log( lvl, msg ):
	if vy >= lvl: print( msg )

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
developMode = Config.get( 'OPTIONS', 'develop_mode')
vy = int(Config.get( 'OPTIONS', 'verbosety_level' ))
unsyncedUsers = Config.get('OPTIONS', 'unsynced_users').split(',')

# LDAP config
LDAPUserName = Config.get('LDAP', 'LDAPUserName')
LDAPPassword = Config.get('LDAP', 'LDAPPassword')
LDAPgroup = Config.get('LDAP', 'LDAPgroup')
LDAPServer = Config.get('LDAP', 'LDAPServer')
LDAPBaseDN = Config.get('LDAP', 'LDAPBaseDN')

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


for n in range(6):
	try:
		# Setup LDAP connection
		l = ldap.initialize(LDAPServer)
		l.protocol_version = ldap.VERSION3
		l.simple_bind_s(LDAPUserName, LDAPPassword)
		break
	except ldap.LDAPError as e:  
		log( 0, e )
		log( 0, "retry {0} / 5".format( n ))
		time.sleep( 4 )
	if n >= 5:
		raise Exception("couldn't connect to LDAP")
	
for n in range(6):
	try:
		# Setup iRODS connection
		sess = iRODSSession(host=iRODShost, port=iRODSport, user=iRODSuser, password=iRODSpassword, zone=iRODSzone)
		break	
	except irods.exception.NetworkException as e: 
		log( 0, e )
		log( 0, "retry {0} / 5".format( n ))
		time.sleep( 4 )
	if n >= 5:
		raise Exception("couldn't connect to iRods")
	
	
# Get users from LDAP
log( 2, "getting list of users from LDAP" )
ldap_users = get_users_from_ldap(l)
log( 1, "LDAP users found: %d" % len(ldap_users) )
# Get users from irods
irods_users = syncable_irods_users( sess, unsyncedUsers )
log( 1, "iRods users found: %d" % len(irods_users) )

# remove obsolete users from irods
remove_obsolete_irods_users( sess, ldap_users, irods_users)

log( 1, "Syncing groups to irods (NOT IMPLEMENTED YET!)")
group2users = get_ldap_groups_and_uuid( l )
for group in group2users:
	provide_group( sess, group )

# Loop over ldap users and create or update as necessary
log( 1, "Syncing found LDAP entries to iRods:" )
n=0
for user in ldap_users:
    # Print username
    log( 1, "\tsyncing LDAP user: " + user.uid )
    if user.uid in unsyncedUsers:
    	log( 0, "\tfound an ldap-user with username %s, who is in list of unsynced_users. Ignoring it." % user.uid )
    	continue
    irodsUser = None

    # Check if user exists
    existsUsername = True
    try:
        irodsUser = sess.users.get( user.uid )
    except UserDoesNotExist:
        existsUsername = False

    # If user does not exists create user
    if not existsUsername:
        try:
            if dryRun != "true":
            	 create_new_irods_user( sess, user )
            log( 1, "\t" + user.uid + " created")
            toAddress =  user.mail
            # UNCOMMENT line below to override the user's e-mail address (for testing purposes)
            # toAddress = "m.coonen@maastrichtuniversity.nl"
            if dryRun != "true" and sendEmail == "true":
                send_welcome_email(fromAddress, toAddress, smtpServer, smtpPort)
            if sendEmail == "true":
                # Print debug statement regardless of dryRun option
                log( 2, "\tWelcome e-mail sent to " + toAddress)
        except Exception as e:
            log( 0, "\tUser creation error")
            log( 0, e )
    else:
        sync_existing_irods_user( sess, irodsUser, user )
    
    # Add the user to the group DH-ingest (= ensures that user is able to create and ingest dropzones)
    add_user_to_group( sess, "DH-ingest", user.uid )
   
    n=n+1
log( 1, "synced %d LDAP Entries to iRods" % n )
