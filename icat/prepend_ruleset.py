#!/usr/bin/env python

# Inspired by: https://github.com/irods/irods/issues/3020

import json
import sys

def main(path_to_server_config, name_of_new_rule_file):
    with open(path_to_server_config, 'r+') as f:
        server_config = json.load(f)
        server_config['re_rulebase_set'].insert(0, {'filename': name_of_new_rule_file})
        f.seek(0)
        json.dump(server_config, f, indent=4, sort_keys=True)
        f.truncate()

if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit('Usage: {0} path_to_server_config name_of_new_rule_to_add'.format(sys.argv[0]))
    path_to_server_config = sys.argv[1]
    name_of_new_rule_to_add = sys.argv[2]
    main(path_to_server_config, name_of_new_rule_to_add)
	