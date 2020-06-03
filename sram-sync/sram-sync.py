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
import re
from datetime import datetime

from enum import Enum
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

from ldap_helper import *
from irods_helper import *

##########################################################

def log( lvl, msg ):
	if vy >= lvl: print( msg )        
	                                                                
##########################################################
# either a default password is given (via config.ini), or a random alpha string is generated
def create_new_irods_user_password():
	if newUsersPassword:
		return newUsersPassword
	chars = "abcdefghijklmnopqrstuvw"
	pwdSize = 20
	return ''.join((random.choice(chars)) for x in range(pwdSize))
 
##########################################################

class UserAVU(Enum):
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
		self.iRodsUser = None
		
	def __repr__(self):
		return "User( uid:{}, displayName: {}, email: {}, iRodsUser: {})".format( self.uid, self.displayName, self.email, self.iRodsUser )
		
	@classmethod
	def createForLDAPEntry( self, ldap_entry ):
		uid = read_ldap_attribute( ldap_entry, 'uid' )
		mail= read_ldap_attribute( ldap_entry, 'mail' )
		cn = read_ldap_attribute( ldap_entry, 'cn' )
		displayName = read_ldap_attribute( ldap_entry, 'displayName' )
		name = uid
		if cn: name = cn
		return mUser( uid, name, mail )
		
		
	#simply write the model user to irods, 
	#set password and AVUs for existing attributes
	def createNewUser( self, irodsSession, dryRun ):
		if dryRun:
			return
		log( 1, "\t\tcreate a new irods user: %s" % self.uid )
		NewIRodsUser = irodsSession.users.create( self.uid, 'rodsuser')
		if self.email: NewIRodsUser.metadata.add( UserAVU.EMAIL.value, self.email )
		if self.displayName: NewIRodsUser.metadata.add( UserAVU.DISPLAY_NAME.value, self.displayName )
		password = create_new_irods_user_password() 
		irodsSession.users.modify( self.uid, 'password', password )
		self.iRodsUser = NewIRodsUser
		# Add the user to the group DH-ingest (= ensures that user is able to create and ingest dropzones)
		add_user_to_group( irodsSession, "DH-ingest", self.uid )
		return self.iRodsUser

    
	def updateExistingUser( self, irodsSession, dryRun ):
		if dryRun:
			return
		log( 1, "\t\tchanging existing irods user:" + self.uid )
		try:
			#remove_all_AVUs( irodsUser )
			#read current AVUs and change if needed
			existingAVUs = get_all_AVUs( self.iRodsUser )
			log( 2, "\t\texisting AVUs BEFORE: " + str(existingAVUs) )
			#careful: because the list of existing AVUs is not updated changing a key multiple times will lead to strange behavior! 
			set_singular_AVU( self.iRodsUser, existingAVUs, 'test', 'some new value', mUser.AVU_KEYS )
			set_singular_AVU( self.iRodsUser, existingAVUs, UserAVU.EMAIL.value, self.email, mUser.AVU_KEYS )
			set_singular_AVU( self.iRodsUser, existingAVUs, UserAVU.DISPLAY_NAME.value, self.displayName, mUser.AVU_KEYS )
		except iRODSException as error:
			log( 0, "error:" + str(error) )	
		existingAVUs = get_all_AVUs( self.iRodsUser )
		log( 2, "\t\texisting AVUs AFTER: " + str(existingAVUs) )
		return self.iRodsUser


	def syncToIRods( self, irodsSession, dryRun, created, updated, failed ):
		# Check if user exists
		existsUsername = True
		existString = "existing"
		try:
			existingIRodsUser = irodsSession.users.get( self.uid )
			self.iRodsUser = existingIRodsUser
		except UserDoesNotExist:
			existsUsername = False
			existString = "non-existing"
		# If user does not exists create user
		if not existsUsername:
			try:
				if not dryRun:
					self.iRodsUser = self.createNewUser( irodsSession, dryRun )
				log( 2, "\t" + self.uid + " created")
				if created:
					created()
			except Exception as e:
				log( 0, "\tUser creation error")
				log( 0, e )
				if failed:
					failed()
		else:
			try:
				if not dryRun:
					self.iRodsUser = self.updateExistingUser( irodsSession, dryRun )	
				log( 2, "\t" + self.uid + " updated")
			except Exception as e:
				log( 0, "\tUser update error")
				log( 0, e )
				if failed:
					failed()

##########################################################
class mGroup:
	LDAP_ATTRIBUTES = ['*']  # all=*
	AVU_KEYS = []

	def __init__(self, groupName, memberUids=[]):
		self.groupName = groupName
		self.memberUids = memberUids
		self.iRodsGroup = None

	def __repr__(self):
		return "Group( groupName:{}, memberUids: {},  iRodGroup: {})".format( self.groupName, self.memberUids, self.iRodsGroup )
		
	@classmethod
	# b'uid=p.vanschayck@maastrichtuniversity.nl,ou=users,dc=datahubmaastricht,dc=nl'
	def getGroupMemberUids( cls, userDN ):
		dn = userDN.decode("utf-8").strip()
		userDict = dict(re.findall(r'([\w]+)=([\w\.@]+)', dn))
		return userDict.get( 'uid', None)
		
	@classmethod
	def createForLDAPEntry( cls, ldap_entry ):
		groupName = read_ldap_attribute( ldap_entry, 'cn' )
		#get us an array of all member-attributes, which contains DNs: [ b'cn=empty-membership-placeholder',  b'uid=p.vanschayck@maastrichtuniversity.nl,ou=users,dc=datahubmaastricht,dc=nl', ...]
		groupMemberDNs = ldap_entry.get(  'member', [b""])
		groupMemberUids = list( filter( lambda x: not x == None, map( mGroup.getGroupMemberUids, groupMemberDNs ) ) )
		#group2users[ groupName ] = groupMemberUids
		return mGroup( groupName, groupMemberUids )
		
	def writeToIrods( self, sess, dryRun, created, updated, failed ):
		group = None
		# Check if the group exists
		existsGroup = True
		try:
			group = sess.user_groups.get( self.groupName )   
			self.iRodsGroup = group
		except UserGroupDoesNotExist:
			existsGroup = False

		if not existsGroup:
			try:
				if not dryRun:
					iRodsGroup = sess.user_groups.create( self.groupName )
					log( 1, "\t\t\tGroup %s created" %  self.groupName )
					if created:
						created()
			except:
				log( 0, "Group %s Creation error" % self.groupName )
				if failed:
					failed()
		else:
			log( 1,"\t\t\tGroup %s already exists" % self.groupName )
			if updated:
				updated()
				
		return group
		
	@classmethod
	def removeGroupFromIRods( cls, sess, groupName ):
		# NEEDS FIX C: remove users from group?
		#   getmembers(self, name):
      #   removemember(self, group_name, user_name, user_zone=""):
		# NEEDS FIX C: move collections/files to somewhere?
      # raise NotImplementedError( "ups" )
      #existingIRodsUser = irodsSession.users.get( groupName )
		sess.users.remove( groupName, user_zone="nlmumc")
	      
##########################################################
##########################################################
##########################################################


def syncable_irods_users( sess, unsyncedUsers ):
	irodsUserNamesSet = set()
	#filter only rodsusers, filter the special users, check wich one are not in the LDAP list
	query = sess.query(User.name, User.id, User.type ).filter( 
     Criterion('=', User.type, 'rodsuser') )
	n = 0
	for result in query:
		n=n+1
		if not result[ User.name ] in unsyncedUsers:
			irodsUserNamesSet.add( result[ User.name] )
	log( 2, "\tiRods users found: {} (allowed for synchronization: {})".format( n, len(irodsUserNamesSet) ) )
	return irodsUserNamesSet
	
##########################################################
#get all the relevant attributes of all users in LDAP, returns an array with dictionaries
def get_users_from_ldap(l):
    searchFilter = "(objectClass=*)"
    return for_ldap_entries_do( l, LDAPUsersBaseDN, searchFilter, mUser.LDAP_ATTRIBUTES, mUser.createForLDAPEntry )	

##########################################################
def remove_obsolete_irods_users( sess, ldap_users, irods_users ):
	log( 1, "\tdeleting obsolete irods users..." )
	deletion_candidates = irods_users.copy()
	for ldap_user in ldap_users:
		deletion_candidates.discard( ldap_user.uid )
	log( 1, "\tidentified %d obsolete irods users for deletion" % len(deletion_candidates) )
	#print( deletion_candidates )	
	for uid in deletion_candidates:
		user = sess.users.get( uid )
		log( 2, "\t\tdeleting user: {}".format( uid ) )
		if not dryRun:
			#how to remove user from groups?
			#group.removemember(user.name)
			remove_all_AVUs( user )
			user.remove()
			#remove_unused_metadata( sess )

##########################################################

def syncLDAPUsersToIrods( ldap, irods, dryRun, deleteUsers ):
	log( 1, "Syncing users to iRods:" )
	
	ldap_users = get_users_from_ldap( ldap )
	log( 1, "LDAP users found: %d" % len(ldap_users) )

	irods_users = syncable_irods_users( irods, unsyncedUsers )
	
	# remove obsolete users from irods
	if not dryRun and deleteUsers:
		remove_obsolete_irods_users( irods, ldap_users, irods_users)

	# Loop over ldap users and create or update as necessary
	log( 1, "Syncing found LDAP entries to iRods:" )
	n=0
	for user in ldap_users:
		n=n+1
		# Print username
		log( 1, "--\tsyncing LDAP user {}/{}: {}".format( n, len(ldap_users), user.uid ) )
    
		if dryRun or (not syncUsers):
			log( 1, "\tsyncing of users not permitted. User {} will no be changed/created".format( user.uid ) )
			continue
		 	
		created = lambda: send_welcome_email(user.displayName, fromAddress, user.email, smtpServer, smtpPort)
		user.syncToIRods( irods, dryRun, created, None, None ) 	
    	
		#if not dryRun and syncUsers and syncGroups:
		#	# Add the user to the group DH-ingest (= ensures that user is able to create and ingest dropzones)
		#	#add_user_to_group( irods, "DH-ingest", user.uid )
		#	pass
	return ldap_users

##########################################################
##########################################################
##########################################################	

def remove_obsolete_irods_groups( sess, ldap_group_names, irods_group_names ):
	log( 1, "\tdeleting obsolete irods groups..." )
	deletion_candidates = set()
	for irods_group in irods_group_names:
		if (irods_group not in ldap_group_names):
			deletion_candidates.add( irods_group )
	log( 1, "\tidentified %d obsolete irods groups for deletion" % len(deletion_candidates) )
	#print( deletion_candidates )	
	for group_name in deletion_candidates:
		log( 2, "\t\tdeleting group: {}".format( group_name ) )
		mGroup.removeGroupFromIRods( sess, group_name ) 
	#	user = sess.users.get( uid )
	#	log( 1, "\t\twill delete user %s" % uid )
	#	if not dryRun:
	#		#how to remove user from groups?
	#		#group.removemember(user.name)
	#		remove_all_AVUs( user )
	#		user.remove()
	#remove_unused_metadata( sess )

##########################################################

#get all groups from LDAP
def get_ldap_groups( l ):
	groupName2groups = dict()
	arrayOfGroups = for_ldap_entries_do( l, LDAPGroupsBaseDN, "(objectClass=groupOfNames)", ["*"], mGroup.createForLDAPEntry )	
	for group in arrayOfGroups:
		groupName2groups[ group.groupName ] = group 
	return groupName2groups

########################################################## 
def add_user_to_group( sess, groupName, userName ):
	group = sess.user_groups.get( groupName )
	try:
		if not dryRun:
			group.addmember(userName)
			log( 1, "\t" + userName + " added to group " + groupName )
	except CATALOG_ALREADY_HAS_ITEM_BY_THAT_NAME:
		log( 2, "\tUser already in group " + groupName )
	except Exception as e:
		log( 1, "could not add user %s to group %s %s" % (userName, groupName, e) )


##########################################################

def syncLDAPGroupsToIrods( ldap, irods, dryRun, deleteGroups ):
	log( 1, "Syncing groups to irods:")
	 
	groupName2group = get_ldap_groups( ldap )
	log( 2, "\tLDAP groups found: %d" % len(groupName2group) )
	
	irods_groups_query = irods.query(User).filter( User.type == 'rodsgroup' )
	irods_group_names = [x[User.name] for x in irods_groups_query]
	syncable_irods_groups = set( filter( lambda x: not x in unsyncedGroups, irods_group_names  ) )
	log( 2, "\tiRods groups found: {} (allowed for synchronization: {})".format( len(irods_group_names), len(syncable_irods_groups) ) )
	
	if not dryRun and deleteGroups:
		remove_obsolete_irods_groups( irods, groupName2group.keys(), syncable_irods_groups)
		
	n=0
	for (groupName, group) in groupName2group.items():
		n=n+1
		log( 1, "--\tsyncing LDAP group {}/{}: {}".format( n, len(groupName2group), groupName ) )
		if not dryRun: group.writeToIrods( irods, dryRun, None, None, None )
		else: log( 1, "\tsyncing of groups not permitted. Group {} will no be changed/created".format( groupName ) )
		
	return groupName2group


##########################################################

def syncGroupMemberships( ldap, irods, ldapUsers, ldapGroups, dryRun ):
	log( 1, "Syncing group members to irods:")
	
	n=0
	for (groupName, group) in ldapGroups.items():
		n=n+1
		log( 1, "--\tsyncing members for LDAP group {}/{}: {}".format( n, len(ldapGroups), groupName ) )
		if not dryRun: group.writeToIrods( irods, dryRun, None, None, None )
		else: log( 1, "\tsyncing of groups not permitted. Group {} will no be changed/created".format( groupName ) )
   	

##########################################################
##########################################################
##########################################################

def send_welcome_email(displayName, fromAddress, toAddress, smtpServer, smtpPort):
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
    html = html.replace("PLACEHOLDER_USERNAME", displayName )

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
##########################################################
##########################################################

startTime = datetime.now()
print( "SRAM-SYNC started at: {}".format( startTime ) )
# Config Parser
Config = configparser.ConfigParser()
if len(sys.argv) > 1:
    config = sys.argv[1]
else:
    config = 'config.ini'
Config.read(config)

# Options config
dryRun = Config.get('OPTIONS', 'dry_run') == "true"
sendEmail = Config.get('OPTIONS', 'send_email') == "true"
newUsersPassword = Config.get( 'OPTIONS', 'new_users_password')
syncUsers = Config.get( 'OPTIONS', 'sync_users') == "true"
deleteUsers = Config.get( 'OPTIONS', 'delete_existing_users' ) == "true"
syncGroups = Config.get( 'OPTIONS', 'sync_groups') == "true"
deleteGroups = Config.get( 'OPTIONS', 'delete_existing_groups') == "true"
vy = int(Config.get( 'OPTIONS', 'verbosity' ))
unsyncedUsers = Config.get('OPTIONS', 'unsynced_users').split(',')
unsyncedGroups = Config.get('OPTIONS', 'unsynced_groups').split(',')

# LDAP config
LDAPUserName = Config.get('LDAP', 'LDAPUserName')
LDAPPassword = Config.get('LDAP', 'LDAPPassword')
LDAPgroup = Config.get('LDAP', 'LDAPgroup')
LDAPServer = Config.get('LDAP', 'LDAPServer')
LDAPUsersBaseDN = Config.get('LDAP', 'LDAPUsersBaseDN')
LDAPGroupsBaseDN = Config.get('LDAP', 'LDAPGroupsBaseDN')

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

if dryRun:
    print("EXECUTING SCRIPT IN DRY MODE! No changes will be made to iCAT. No e-mails will be sent. \n")

ldap = getLDAPConnection(LDAPServer, LDAPUserName, LDAPPassword)
irods = getIRodsConnection(iRODShost, iRODSport, iRODSuser, iRODSpassword, iRODSzone)

ldapUsers = None
ldapGroups = None
if syncUsers:
	ldapUsers = syncLDAPUsersToIrods( ldap, irods, dryRun, deleteUsers )

if syncGroups:
	ldapGroups = syncLDAPGroupsToIrods( ldap, irods, dryRun, deleteGroups )
	
if syncUsers and syncGroups:
	syncGroupMemberships( ldap, irods, ldapUsers, ldapGroups, dryRun )
	
endTime = datetime.now()
print( "SRAM-SYNC finished at: {} (took {} sec)".format( endTime, (endTime-startTime).total_seconds() ) )
    