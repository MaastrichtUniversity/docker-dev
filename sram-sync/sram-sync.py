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
import argparse

# Setup logging
log_level = os.environ['LOG_LEVEL']
logging.basicConfig(level=logging.getLevelName(log_level), format='%(asctime)s %(levelname)s %(message)s')
logger = logging.getLogger('root')

# Options config
# TO DO: ALL golbals in CAPITAL_CASE_WITH_UNDERSCORE
DEFAULT_USER_PASSWORD = os.environ['DEFAULT_USER_PASSWORD']

SYNC_USERS = True
DELETE_USERS = True
SYNC_GROUPS = True
DELETE_GROUPS = True

#NEEDS FIX A: instead of blacklists we should use an AVY on groups/users indicating weather it should be synced or not
UNSYNCED_USERS  = "service-pid,service-mdl,service-disqover,service-dropzones,service-surfarchive,DH-project-admins".split(',')
UNSYNCED_GROUPS = "rodsadmin,DH-ingest,public,DH-project-admins".split(',')

# LDAP config
LDAP_USER = os.environ['LDAP_USER']
LDAP_PASS = os.environ['LDAP_PASS']
#LDAPgroup = Config.get('LDAP', 'LDAPgroup')
LDAP_HOST = os.environ['LDAP_HOST']

LDAP_GROUP = "Users"
LDAP_USER_BASE_DN = "ou=users,DC=datahubmaastricht,DC=nl"
LDAP_GROUPS_BASE_DN = "ou=groups,DC=datahubmaastricht,DC=nl"

# iRODS config
IRODS_HOST = os.environ['IRODS_HOST']
IRODS_USER = os.environ['IRODS_USER']
IRODS_PASS = os.environ['IRODS_PASS']

#IRODS_GROUP = Config.get('iRODS', 'group')
IRODS_PORT = 1247
IRODS_ZONE = "nlmumc"

##########################################################

def parse_arguments():
    parser = argparse.ArgumentParser(
        description=__doc__,  # printed with -h/--help
        # Don't mess with format of description
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("commit", action='store_true', help="write any updates/changes to iRODS")
    parser.add_argument("scheduled", action='store_true', help="if set runs every few minutes")
    settings = parser.parse_args()    
    return settings
                                                          
##########################################################
# either a default password is given (via config.ini), or a random alpha string is generated
def create_new_irods_user_password():
	if DEFAULT_USER_PASSWORD == '':
		return DEFAULT_USER_PASSWORD
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

	def __init__(self, uid, display_name, email):
		self.uid = uid
		self.display_name = display_name
		self.email = email
		self.irods_user = None
		
	def __repr__(self):
		return "User( uid:{}, displayName: {}, email: {}, iRodsUser: {})".format( self.uid, self.display_name, self.email, self.irods_user )
		
	@classmethod
	def create_for_ldap_entry( self, ldap_entry ):
		uid = read_ldap_attribute( ldap_entry, 'uid' )
		mail= read_ldap_attribute( ldap_entry, 'mail' )
		cn = read_ldap_attribute( ldap_entry, 'cn' )
		display_name = read_ldap_attribute( ldap_entry, 'displayName' )
		#here we could decided weather to use the cn or uid as displayName...
		return mUser( uid, cn, mail )
		
		
	#simply write the model user to irods, 
	#set password and AVUs for existing attributes
	def create_new_user( self, irods_session, dry_run ):
		if dry_run:
			return
		logger.info( "create a new irods user: %s" % self.uid )
		NewIRodsUser = irods_session.users.create( self.uid, 'rodsuser')
		if self.email: NewIRodsUser.metadata.add( UserAVU.EMAIL.value, self.email )
		if self.display_name: NewIRodsUser.metadata.add( UserAVU.DISPLAY_NAME.value, self.display_name )
		password = create_new_irods_user_password() 
		irods_session.users.modify( self.uid, 'password', password )
		self.iRodsUser = NewIRodsUser
		# TO DO: is this the correct place? Any other must have groups that I'm missing?
		# Add the user to the group DH-ingest (= ensures that user is able to create and ingest dropzones)
		add_user_to_group( irods_session, "DH-ingest", self.uid )
		return self.irods_user

    
	def update_existing_user( self, irods_session, dry_run ):
		if dry_run:
			return
		logger.info( "changing existing irods user:" + self.uid )
		try:
			#read current AVUs and change if needed
			existing_avus = get_all_avus( self.irods_user )
			logger.debug( "existing AVUs BEFORE: " + str(existing_avus) )
			#careful: because the list of existing AVUs is not updated changing a key multiple times will lead to strange behavior! 
			set_singular_avu( self.irods_user, UserAVU.EMAIL.value, self.email )
			set_singular_avu( self.irods_user, UserAVU.DISPLAY_NAME.value, self.display_name )
		except iRODSException as error:
			logger.error( "error changing AVUs" + str(error) )	
		existing_avus = get_all_avus( self.irods_user)
		logger.debug( "existing AVUs AFTER: " + str(existing_avus) )
		return self.irods_user


	def sync_to_irods( self, irods_session, dry_run, created, updated, failed ):
		# Check if user exists
		exists_username = True
		try:
			self.irods_user = irods_session.users.get( self.uid )
		except UserDoesNotExist:
			exists_username = False
		# If user does not exists create user
		if not exists_username:
			try:
				if not dry_run:
					self.irods_user = self.create_new_user( irods_session, dry_run )
				logger.debug( "User: " + self.uid + " created")
				if created:
					created()
			except Exception as e:
				logger.error( "User creation error: "+str(e) )
				if failed:
					failed()
		else:
			try:
				if not dry_run:
					self.irods_user = self.update_existing_user( irods_session, dry_run )	
				logger.debug( "User: " + self.uid + " updated")
			except Exception as e:
				logger.error( "User update error: " +str(e) )
				if failed:
					failed()

##########################################################
class mGroup:
	LDAP_ATTRIBUTES = ['*']  # all=*
	AVU_KEYS = []

	def __init__(self, group_name, member_uids=[]):
		self.group_name = group_name
		self.member_uids = member_uids
		self.irods_group = None

	def __repr__(self):
		return "Group( group_name:{}, member_uids: {},  irods_group: {})".format( self.group_name, self.member_uids, self.iRodsGroup )

		
	@classmethod
	# b'uid=p.vanschayck@maastrichtuniversity.nl,ou=users,dc=datahubmaastricht,dc=nl'
	def get_group_member_uids( cls, user_dn ):
		dn = user_dn.decode("utf-8").strip()
		user_dict = dict(re.findall(r'([\w]+)=([\w\.@]+)', dn))
		return user_dict.get( 'uid', None)
		
	@classmethod
	def create_for_ldap_entry( cls, ldap_entry ):
		group_name = read_ldap_attribute( ldap_entry, 'cn' )
		#get us an array of all member-attributes, which contains DNs: [ b'cn=empty-membership-placeholder',  b'uid=p.vanschayck@maastrichtuniversity.nl,ou=users,dc=datahubmaastricht,dc=nl', ...]
		group_member_dns = ldap_entry.get(  'member', [b""])
		group_member_uids = list( filter( lambda x: not x == None, map( mGroup.get_group_member_uids, group_member_dns ) ) )
		return mGroup( group_name, group_member_uids )
		
	def write_to_irods( self, sess, dry_run, created, updated, failed ):
		# Check if the group exists
		exists_group = True
		try:
			self.irods_group = sess.user_groups.get( self.group_name )   
		except UserGroupDoesNotExist:
			exists_group = False

		if not exists_group:
			try:
				if not dry_run:
					self.irods_group = sess.user_groups.create( self.group_name )
					logger.info( "Group %s created" %  self.group_name )
					if created:
						created()
			except:
				logger.error( "Group %s Creation error" % self.group_name )
				if failed:
					failed()
		else:
			logger.info( "Group %s already exists" % self.group_name )
			#TO DO: is there a difference between Group-ID and Group-DisplayName? If so, set an AVU here!
			if updated:
				updated()
				
		return self.irods_group
		
	@classmethod
	def remove_group_from_irods( cls, sess, group_name ):
		sess.users.remove( group_name, user_zone=IRODS_ZONE)
	      
##########################################################
##########################################################
##########################################################


def syncable_irods_users( sess, unsynced_users ):
	irods_user_names_set = set()
	#filter only rodsusers, filter the special users, check wich one are not in the LDAP list
	query = sess.query( User.name, User.id, User.type ).filter( 
     Criterion('=', User.type, 'rodsuser') )
	n = 0
	for result in query:
		n=n+1
		if not result[ User.name ] in unsynced_users:
			irods_user_names_set.add( result[ User.name] )
	logger.debug( "iRods users found: {} (allowed for synchronization: {})".format( n, len(irods_user_names_set) ) )
	return irods_user_names_set
	
##########################################################
#get all the relevant attributes of all users in LDAP, returns an array with dictionaries
def get_users_from_ldap(l):
    searchFilter = "(objectClass=*)"
    return for_ldap_entries_do( l, LDAP_USER_BASE_DN, searchFilter, mUser.LDAP_ATTRIBUTES, mUser.create_for_ldap_entry )	

##########################################################
def remove_obsolete_irods_users( sess, ldap_users, irods_users ):
	logger.info( "deleting obsolete irods users..." )
	deletion_candidates = irods_users.copy()
	for ldap_user in ldap_users:
		deletion_candidates.discard( ldap_user.uid )
	logger.info( "identified %d obsolete irods users for deletion" % len(deletion_candidates) )
	#print( deletion_candidates )	
	for uid in deletion_candidates:
		user = sess.users.get( uid )
		logger.debug( "deleting user: {}".format( uid ) )
		if not dry_run:
			user.remove()

##########################################################

def sync_ldap_users_to_irods( ldap, irods, dry_run ):
	logger.info( "Syncing users to iRods:" )
	
	ldap_users = get_users_from_ldap( ldap )
	logger.info( "LDAP users found: %d" % len(ldap_users) )

   #TO DO: give irods users an AVU to mark them as SRAM_SYNCED true/false, instead of using a blacklist in config.ini
	irods_users = syncable_irods_users( irods, UNSYNCED_USERS )
	
	# remove obsolete users from irods
	if not dry_run and DELETE_USERS:
		remove_obsolete_irods_users( irods, ldap_users, irods_users)

	# Loop over ldap users and create or update as necessary
	logger.info( "Syncing found LDAP entries to iRods:" )
	n=0
	for user in ldap_users:
		n=n+1
		# Print username
		logger.info( "--syncing LDAP user {}/{}: {}".format( n, len(ldap_users), user.uid ) )
    
		if dry_run or (not SYNC_USERS):
			logger.info( "syncing of users not permitted. User {} will no be changed/created".format( user.uid ) )
			continue
		 	
		user.sync_to_irods( irods, dry_run, None, None, None ) 	
    	
	return ldap_users

##########################################################
##########################################################
##########################################################	

def remove_obsolete_irods_groups( sess, ldap_group_names, irods_group_names ):
	logger.info( "deleting obsolete irods groups..." )
	deletion_candidates = set()
	for irods_group in irods_group_names:
		if (irods_group not in ldap_group_names):
			deletion_candidates.add( irods_group )
	logger.info( "identified %d obsolete irods groups for deletion" % len(deletion_candidates) )
	#print( deletion_candidates )	
	for group_name in deletion_candidates:
		logger.debug( "tdeleting group: {}".format( group_name ) )
		mGroup.remove_group_from_irods( sess, group_name ) 

##########################################################

#get all groups from LDAP
def get_ldap_groups( l ):
	group_name_2_groups = dict()
	ldap_groups = for_ldap_entries_do( l, LDAP_GROUPS_BASE_DN, "(objectClass=groupOfNames)", ["*"], mGroup.create_for_ldap_entry )	
	for group in ldap_groups:
		group_name_2_groups[ group.group_name ] = group 
	return group_name_2_groups

########################################################## 
def add_user_to_group( sess, group_name, user_name ):
	irods_group = sess.user_groups.get( group_name )
	try:
		if not dry_run:
			irods_group.addmember(user_name)
			logger.debug( "User: " + user_name + " added to group " + group_name )
	except CATALOG_ALREADY_HAS_ITEM_BY_THAT_NAME:
		logger.debug( "User {} already in group {} ".format( user_name, group_name ) )
	except Exception as e:
		logger.info( "could not add user {} to group {}. '{}'".format(user_name, group_name, e) )


########################################################## 
def remove_user_from_group( sess, group_name, user_name ):
	irods_group = sess.user_groups.get( group_name )
	try:
		if not dry_run:
			irods_group.removemember( user_name )
			logger.debug( "User: " + user_name + " removed from group " + group_name )
	except Exception as e:
		logger.info( "could not remove user {} from group {}. '{}'".format( user_name, group_name, e ) )
		
##########################################################

#TO DO: change to.format()
def sync_ldap_groups_to_irods( ldap, irods, dry_run ):
	logger.info( "Syncing groups to irods:")
	 
	group_name_2_group = get_ldap_groups( ldap )
	logger.debug( "LDAP groups found: %d" % len(group_name_2_group) )
	
	irods_groups_query = irods.query(User).filter( User.type == 'rodsgroup' )
	irods_group_names = [x[User.name] for x in irods_groups_query]
	syncable_irods_groups = set( filter( lambda x: not x in UNSYNCED_GROUPS, irods_group_names  ) )
	logger.debug( "iRods groups found: {} (allowed for synchronization: {})".format( len(irods_group_names), len(syncable_irods_groups) ) )
	
	if not dry_run and DELETE_GROUPS:
		remove_obsolete_irods_groups( irods, group_name_2_group.keys(), syncable_irods_groups)
		
	n=0
	for (group_name, group) in group_name_2_group.items():
		n=n+1
		logger.info( "--syncing LDAP group {}/{}: {}".format( n, len(group_name_2_group), group_name ) )
		if not dry_run: 
			group.write_to_irods( irods, dry_run, None, None, None )
		else: 
			logger.info( "syncing of groups not permitted. Group {} will no be changed/created".format( group_name ) )
		
	return group_name_2_group


##########################################################
def diff_member_lists( ldapMembers, iRodsMembers ):
	if not bool(iRodsMembers):
		return set(), ldapMembers, set()
	if not bool(ldapMembers):
		return set(), set(), iRodsMembers
	stay = set( filter( lambda x: x in iRodsMembers, ldapMembers ) )
	add = set( filter( lambda x: x not in iRodsMembers, ldapMembers ) )
	remove = set( filter( lambda x: x not in ldapMembers, iRodsMembers ) )
	return stay, add, remove	
	
##########################################################
def sync_group_memberships( ldap, irods, ldap_groups, dry_run ):
	logger.info( "Syncing group members to irods:")
	
	#create a mapping of irods group names to the member uids
	irods_groups_2_users = dict()
	for result in irods.query(UserGroup,User): 
		irods_group = iRODSUserGroup( irods.user_groups, result)
		irods_user = iRODSUser(irods.users, result) 
		if irods_group.id == irods_user.id:
			continue
		if irods_group.name not in irods_groups_2_users:
			irods_groups_2_users[ irods_group.name ] = set()
		else:
			irods_groups_2_users[ irods_group.name ].add( irods_user.name )
	
	#check each LDAP Group against each irodsGroup	
	n=0
	for (group_name, group) in ldap_groups.items():
		n=n+1
		logger.info( "syncing memberships for group {}...".format( group_name ) )
		irods_member_list = irods_groups_2_users.get( group_name, set() )
		stay, add, remove = diff_member_lists( group.member_uids, irods_member_list )
		logger.info( "memberships for group {}: {} same, {} added, {} removed".format( group_name, len(stay), len(add), len(remove) ) )
	
		if not dry_run:
			for uid in add:
				add_user_to_group( irods, group_name, uid )
		
			for uid in remove:
				remove_user_from_group( irods, group_name, uid )


##########################################################
##########################################################
##########################################################

def main( dry_run ):
	start_time = datetime.now()
	logger.info( "SRAM-SYNC started at: {}".format( start_time ) )

	if dry_run:
		logger.info("EXECUTING SCRIPT IN DRY MODE! No changes will be made to iCAT.")

	ldap = get_ldap_connection(LDAP_HOST, LDAP_USER, LDAP_PASS )
	irods = get_irods_connection( IRODS_HOST, IRODS_PORT, IRODS_USER, IRODS_PASS, IRODS_ZONE )

	ldap_users = None
	ldap_groups = None
	if SYNC_USERS:
		ldap_users = sync_ldap_users_to_irods( ldap, irods, dry_run )

	if SYNC_GROUPS:
		ldap_groups = sync_ldap_groups_to_irods( ldap, irods, dry_run )
	
	if SYNC_USERS and SYNC_GROUPS:
		sync_group_memberships( ldap, irods, ldap_groups, dry_run )
	
	end_time = datetime.now()
	logger.info( "SRAM-SYNC finished at: {} (took {} sec)".format( end_time, (end_time-start_time).total_seconds() ) )
    
 
##########################################################   
def sigterm_handler(_signal, _stack_frame):
    sys.exit(0)
 
if __name__ == "__main__":
    # Handle the SIGTERM signal from Docker
    signal.signal(signal.SIGTERM, sigterm_handler)
    settings = parse_arguments()
    
    dry_run = ( settings.commit == False )

    try:
      exit_code = main( dry_run )
      if settings.scheduled:
         while True:
            main( dry_run ) 
            time.sleep(5*60)
      sys.exit( exit_code )
    finally:
        # Perform any clean up of connections on closing here
        logger.info("Exiting")
        