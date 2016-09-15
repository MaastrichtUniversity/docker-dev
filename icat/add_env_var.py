#!/usr/bin/env python

# Inspired by: https://github.com/irods/irods/issues/3020

import json
import sys

def main(path_to_server_config, key, value):
    with open(path_to_server_config, 'r+') as f:
        server_config = json.load(f)
        server_config['environment_variables'].update({key: value})
        f.seek(0)
        json.dump(server_config, f, indent=4, sort_keys=True)
        f.truncate()

if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit('Usage: {0} path_to_server_config key value'.format(sys.argv[0]))
    path_to_server_config = sys.argv[1]
    key = sys.argv[2]
    value = sys.argv[3]
    main(path_to_server_config, key, value)