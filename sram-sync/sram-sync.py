import signal
import sys
import os
import logging

from irods.session import iRODSSession
from irods.access import iRODSAccess
from irods.column import Criterion
from irods.models import User, UserGroup
from irods.exception import *
from irods.user import iRODSUser, iRODSUserGroup

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

from ldap_helper import *
from irods_helper import *


# Setup logging
log_level = os.environ['LOG_LEVEL']
logging.basicConfig(level=logging.getLevelName(log_level), format='%(asctime)s %(levelname)s %(message)s')
logger = logging.getLogger('root')

                                                          
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
		#name = uid
		#if not cn: name = '' #cn
		return mUser( uid, cn, mail )
		
		
	#simply write the model user to irods, 
	#set password and AVUs for existing attributes
	def createNewUser( self, irodsSession, dryRun ):
		if dryRun:
			return
		logger.info( "\t\tcreate a new irods user: %s" % self.uid )
		NewIRodsUser = irodsSession.users.create( self.uid, 'rodsuser')
		if self.email: NewIRodsUser.metadata.add( UserAVU.EMAIL.value, self.email )
		if self.displayName: NewIRodsUser.metadata.add( UserAVU.DISPLAY_NAME.value, self.displayName )
		password = create_new_irods_user_password() 
		irodsSession.users.modify( self.uid, 'password', password )
		self.iRodsUser = NewIRodsUser
		# TO DO: is this the correct place? Any other must have groups that I'm missing?
		# Add the user to the group DH-ingest (= ensures that user is able to create and ingest dropzones)
		add_user_to_group( irodsSession, "DH-ingest", self.uid )
		return self.iRodsUser

    
	def updateExistingUser( self, irodsSession, dryRun ):
		if dryRun:
			return
		logger.info( "\t\tchanging existing irods user:" + self.uid )
		try:
			#read current AVUs and change if needed
			existingAVUs = get_all_AVUs( self.iRodsUser )
			logger.debug( "\t\texisting AVUs BEFORE: " + str(existingAVUs) )
			#careful: because the list of existing AVUs is not updated changing a key multiple times will lead to strange behavior! 
			set_singular_AVU( self.iRodsUser, UserAVU.EMAIL.value, self.email )
			set_singular_AVU( self.iRodsUser, UserAVU.DISPLAY_NAME.value, self.displayName )
		except iRODSException as error:
			logger.error( " error changing AVUs" + str(error) )	
		existingAVUs = get_all_AVUs( self.iRodsUser )
		logger.debug( "\t\texisting AVUs AFTER: " + str(existingAVUs) )
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
				logger.debug( "\t" + self.uid + " created")
				if created:
					created()
			except Exception as e:
				logger.error( "\tUser creation error: "+str(e) )
				if failed:
					failed()
		else:
			try:
				if not dryRun:
					self.iRodsUser = self.updateExistingUser( irodsSession, dryRun )	
				logger.debug( "\t" + self.uid + " updated")
			except Exception as e:
				logger.error( "\tUser update error: " +str(e) )
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
					logger.info( "\t\t\tGroup %s created" %  self.groupName )
					if created:
						created()
			except:
				logger.error( "Group %s Creation error" % self.groupName )
				if failed:
					failed()
		else:
			logger.info( "\t\t\tGroup %s already exists" % self.groupName )
			#TO DO: is there a difference between Group-ID and Group-DisplayName? If so, set an AVU here!
			if updated:
				updated()
				
		return group
		
	@classmethod
	def removeGroupFromIRods( cls, sess, groupName ):
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
	logger.debug( "\tiRods users found: {} (allowed for synchronization: {})".format( n, len(irodsUserNamesSet) ) )
	return irodsUserNamesSet
	
##########################################################
#get all the relevant attributes of all users in LDAP, returns an array with dictionaries
def get_users_from_ldap(l):
    searchFilter = "(objectClass=*)"
    return for_ldap_entries_do( l, LDAPUsersBaseDN, searchFilter, mUser.LDAP_ATTRIBUTES, mUser.createForLDAPEntry )	

##########################################################
def remove_obsolete_irods_users( sess, ldap_users, irods_users ):
	logger.info( "\tdeleting obsolete irods users..." )
	deletion_candidates = irods_users.copy()
	for ldap_user in ldap_users:
		deletion_candidates.discard( ldap_user.uid )
	logger.info( "\tidentified %d obsolete irods users for deletion" % len(deletion_candidates) )
	#print( deletion_candidates )	
	for uid in deletion_candidates:
		user = sess.users.get( uid )
		logger.debug( "\t\tdeleting user: {}".format( uid ) )
		if not dryRun:
			user.remove()

##########################################################

def syncLDAPUsersToIrods( ldap, irods, dryRun, deleteUsers ):
	logger.info( "Syncing users to iRods:" )
	
	ldap_users = get_users_from_ldap( ldap )
	logger.info( "LDAP users found: %d" % len(ldap_users) )

   #TO DO: give irods users an AVU to mark them as SRAM_SYNCED true/false, instead of using a blacklist in config.ini
	irods_users = syncable_irods_users( irods, unsyncedUsers )
	
	# remove obsolete users from irods
	if not dryRun and deleteUsers:
		remove_obsolete_irods_users( irods, ldap_users, irods_users)

	# Loop over ldap users and create or update as necessary
	logger.info( "Syncing found LDAP entries to iRods:" )
	n=0
	for user in ldap_users:
		n=n+1
		# Print username
		logger.info( "--\tsyncing LDAP user {}/{}: {}".format( n, len(ldap_users), user.uid ) )
    
		if dryRun or (not syncUsers):
			logger.info( "\tsyncing of users not permitted. User {} will no be changed/created".format( user.uid ) )
			continue
		 	
		user.syncToIRods( irods, dryRun, None, None, None ) 	
    	
	return ldap_users

##########################################################
##########################################################
##########################################################	

def remove_obsolete_irods_groups( sess, ldap_group_names, irods_group_names ):
	logger.info( "\tdeleting obsolete irods groups..." )
	deletion_candidates = set()
	for irods_group in irods_group_names:
		if (irods_group not in ldap_group_names):
			deletion_candidates.add( irods_group )
	logger.info( "\tidentified %d obsolete irods groups for deletion" % len(deletion_candidates) )
	#print( deletion_candidates )	
	for group_name in deletion_candidates:
		logger.debug( "\t\tdeleting group: {}".format( group_name ) )
		mGroup.removeGroupFromIRods( sess, group_name ) 

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
			logger.debug( "\t" + userName + " added to group " + groupName )
	except CATALOG_ALREADY_HAS_ITEM_BY_THAT_NAME:
		logger.debug( "\tUser {} already in group {} ".format( userName, groupName ) )
	except Exception as e:
		logger.info( "could not add user {} to group {} {}".format(userName, groupName, e) )


########################################################## 
def remove_user_from_group( sess, groupName, userName ):
	group = sess.user_groups.get( groupName )
	try:
		if not dryRun:
			group.removemember( userName )
			logger.debug( "\t" + userName + " removed from group " + groupName )
	except Exception as e:
		logger.info( "could not remove user {} from group {} {}".format(userName, groupName, e) )
		
##########################################################

#TO DO: change to.format()
def syncLDAPGroupsToIrods( ldap, irods, dryRun, deleteGroups ):
	logger.info( "Syncing groups to irods:")
	 
	groupName2group = get_ldap_groups( ldap )
	logger.debug( "\tLDAP groups found: %d" % len(groupName2group) )
	
	irods_groups_query = irods.query(User).filter( User.type == 'rodsgroup' )
	irods_group_names = [x[User.name] for x in irods_groups_query]
	syncable_irods_groups = set( filter( lambda x: not x in unsyncedGroups, irods_group_names  ) )
	logger.debug( "\tiRods groups found: {} (allowed for synchronization: {})".format( len(irods_group_names), len(syncable_irods_groups) ) )
	
	if not dryRun and deleteGroups:
		remove_obsolete_irods_groups( irods, groupName2group.keys(), syncable_irods_groups)
		
	n=0
	for (groupName, group) in groupName2group.items():
		n=n+1
		logger.info( "--\tsyncing LDAP group {}/{}: {}".format( n, len(groupName2group), groupName ) )
		if not dryRun: 
			group.writeToIrods( irods, dryRun, None, None, None )
		else: 
			logger.info( "\tsyncing of groups not permitted. Group {} will no be changed/created".format( groupName ) )
		
	return groupName2group


##########################################################
def diffUserLists( ldapMembers, iRodsMembers ):
	if not bool(iRodsMembers):
		return set(), ldapMembers, set()
	if not bool(ldapMembers):
		return set(), set(), iRodsMembers
	stay = set( filter( lambda x: x in iRodsMembers, ldapMembers ) )
	add = set( filter( lambda x: x not in iRodsMembers, ldapMembers ) )
	remove = set( filter( lambda x: x not in ldapMembers, iRodsMembers ) )
	return stay, add, remove	
	
##########################################################
def syncGroupMemberships( ldap, irods, ldapUsers, ldapGroups, dryRun ):
	logger.info( "Syncing group members to irods:")
	
	irodsGroups2Users = dict()
	
	for result in irods.query(UserGroup,User): 
		irodsGroup = iRODSUserGroup( irods.user_groups, result)
		irodsUser = iRODSUser(irods.users, result) 
		if irodsGroup.id == irodsUser.id:
			continue
		#print( "TEST {} --> {}".format( irodsGroup.name, irodsUser.name ) )
		if irodsGroup.name not in irodsGroups2Users:
			irodsGroups2Users[ irodsGroup.name ] = set()
		else:
			irodsGroups2Users[ irodsGroup.name ].add( irodsUser.name )
	

	#check each ldapGroup agains each irodsGroup	
	n=0
	for (groupName, group) in ldapGroups.items():
		n=n+1
		print( " --> {}".format( groupName ) )
		iRodsMemberList = irodsGroups2Users.get(groupName, set() )
		#print( iRodsMemberList )	
		#print( group.memberUids )
		stay, add, remove = diffUserLists( group.memberUids, iRodsMemberList )
		logger.debug( "\t = {}".format( len(stay) ) )
		logger.debug( "\t + {}".format( len(add) ) )
		logger.debug( "\t - {}".format( len(remove) ) )
	
		for uid in add:
			add_user_to_group( irods, groupName, uid )
		
		for uid in remove:
			remove_user_from_group( irods, groupName, uid )


##########################################################
##########################################################
##########################################################

def main():
	startTime = datetime.now()
	logger.info( "SRAM-SYNC started at: {}".format( startTime ) )
	# Config Parser
	Config = configparser.ConfigParser()
	if len(sys.argv) > 1:
	    config = sys.argv[1]
	else:
 		config = 'config.ini'
	Config.read(config)

	# Options config
	global dryRun
	dryRun = os.environ['LOG_LEVEL'] == "true"
	
	global newUsersPassword, syncUsers, deleteUsers, syncGroups
	global deleteGroups, unsyncedUsers, unsyncedGroups
	newUsersPassword = Config.get( 'OPTIONS', 'new_users_password')
	syncUsers = Config.get( 'OPTIONS', 'sync_users') == "true"
	deleteUsers = Config.get( 'OPTIONS', 'delete_existing_users' ) == "true"
	syncGroups = Config.get( 'OPTIONS', 'sync_groups') == "true"
	deleteGroups = Config.get( 'OPTIONS', 'delete_existing_groups') == "true"
	vy = int(Config.get( 'OPTIONS', 'verbosity' ))
	unsyncedUsers = Config.get('OPTIONS', 'unsynced_users').split(',')
	unsyncedGroups = Config.get('OPTIONS', 'unsynced_groups').split(',')

	#global LDAPUserName, LDAPPassword, LDAPgroup, LDAPServer
	global LDAPUsersBaseDN, LDAPGroupsBaseDN
	# LDAP config
	LDAPUserName = Config.get('LDAP', 'LDAPUserName')
	LDAPPassword = Config.get('LDAP', 'LDAPPassword')
	LDAPgroup = Config.get('LDAP', 'LDAPgroup')
	LDAPServer = Config.get('LDAP', 'LDAPServer')
	LDAPUsersBaseDN = Config.get('LDAP', 'LDAPUsersBaseDN')
	LDAPGroupsBaseDN = Config.get('LDAP', 'LDAPGroupsBaseDN')

	# iRODS config
	global iRODShost, iRODSport, iRODSuser, iRODSpassword, iRODSzone, iRODSgroup
	iRODShost = Config.get('iRODS', 'host')
	iRODSport = Config.get('iRODS', 'port')
	iRODSuser = Config.get('iRODS', 'user')
	iRODSpassword = Config.get('iRODS', 'password')
	iRODSzone = Config.get('iRODS', 'zone')
	iRODSgroup = Config.get('iRODS', 'group')


	if dryRun:
		logger.info("EXECUTING SCRIPT IN DRY MODE! No changes will be made to iCAT.")

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
	logger.info( "SRAM-SYNC finished at: {} (took {} sec)".format( endTime, (endTime-startTime).total_seconds() ) )
    
 
##########################################################   
def sigterm_handler(_signal, _stack_frame):
    sys.exit(0)
 
if __name__ == "__main__":
    # Handle the SIGTERM signal from Docker
    signal.signal(signal.SIGTERM, sigterm_handler)
 
    try:
        sys.exit(main())
    finally:
        # Perform any clean up of connections on closing here
        logger.info("Exiting")
        