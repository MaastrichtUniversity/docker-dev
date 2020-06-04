import ldap
import os
import logging
import time

# Setup logging
log_level = os.environ['LOG_LEVEL']
logging.basicConfig(level=logging.getLevelName(log_level), format='%(asctime)s %(levelname)s %(message)s')
logger = logging.getLogger('root')


##########################################################

def read_ldap_attribute(ldap_entry, key):
	return ldap_entry.get(  key, [b""])[0].decode("utf-8").strip()

##########################################################

def for_ldap_entries_do( l, base_dn, search_filter, retrieve_attributes, callback ):
    return_array = []
    search_scope = ldap.SCOPE_SUBTREE

    # Perform the LDAP search
    id = l.search( base_dn, search_scope, search_filter, retrieve_attributes )
    #all = 1
    # If all is 0, search entries will be returned one at a time as they come in, via separate calls to result().
    # If all is 1, the search response will be returned in its entirety, i.e. after all entries and the final search result have been received.
    result_type, result = l.result(id, all=0)
    while result:
        if result[0] and len( result[0] ) == 2:
            entry = result[0][1]
            if entry:
                function_result = callback( entry )
                return_array.append( function_result )
        result_type, result = l.result(id, all=0)
    return return_array

##########################################################

def get_ldap_connection( LDAP_HOST, LDAP_USER, LDAP_PASS ):
	MAX_TRIES = 5
	SLEEP_INTERVAL = 4
	for n in range(MAX_TRIES+1):
		try:
			# Setup LDAP connection
			l = ldap.initialize(LDAP_HOST)
			l.protocol_version = ldap.VERSION3
			l.simple_bind_s(LDAP_USER, LDAP_PASS)
			return l
		except ldap.LDAPError as e:
			logger.error( str( e ) )
			logger.info( "retry {0} / {1}".format(n,MAX_TRIES))
			time.sleep(SLEEP_INTERVAL)
		if n >= MAX_TRIES:
			raise Exception("couldn't connect to LDAP")