import os
import logging

from irods.session import iRODSSession
from irods.access import iRODSAccess
from irods.column import Criterion
from irods.models import User, UserGroup
from irods.exception import *
from irods.meta import iRODSMeta
from irods.message import GeneralAdminRequest
from irods.api_number import api_number
import time

# Setup logging
log_level = os.environ['LOG_LEVEL']
logging.basicConfig(level=logging.getLevelName(log_level), format='%(asctime)s %(levelname)s %(message)s')
logger = logging.getLogger('root')


##########################################################
def get_all_avus( irods_user ):    
    existing_avus = {}
    for item in irods_user.metadata.items():
       existing_avus[ item.name ] = item.value  
    return existing_avus
    
##########################################################
	 	  
def set_singular_avu( irods_user, avu_key, avu_value ):
	if not avu_value:
		# this doesnt work: irods_user.metadata.remove( avu_key, None, None )
		for avu in irods_user.metadata.items():
			if avu.name == avu_key:
				irods_user.metadata.remove( avu )
	else:
		new_avu = iRODSMeta( avu_key, avu_value )
		irods_user.metadata[ new_avu.name ] = new_avu
	return

##########################################################

def remove_unused_metadata(session):
    message_body = GeneralAdminRequest( 'rm', 'unusedAVUs', '','','','')
    req = iRODSMessage("RODS_API_REQ", msg = message_body,int_info=api_number['GENERAL_ADMIN_AN'])
    with session.pool.get_connection() as conn:
        conn.send(req)
        response=conn.recv()
        if (response.int_info != 0): raise RuntimeError("Error removing unused AVUs")

##########################################################

def get_irods_connection(IRODS_HOST, IRODS_PORT, IRODS_USER, IRODS_PASS, IRODS_ZONE):
	MAX_TRIES = 5
	SLEEP_INTERVAL = 4
	for n in range(MAX_TRIES+1):
		try:
			# Setup iRODS connection
			sess = iRODSSession(host=IRODS_HOST, port=IRODS_PORT, user=IRODS_USER, password=IRODS_PASS, zone=IRODS_ZONE)
			return sess
		except irods.exception.NetworkException as e:
			logger.error( str( e ) )
			logger.info( "retry {0} / {1}".format(n,MAX_TRIES))
			time.sleep(SLEEP_INTERVAL)
		if n >= MAX_TRIES:
			raise Exception("couldn't connect to iRods")

    