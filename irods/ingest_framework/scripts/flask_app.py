import json
import sys

from irods_capability_automated_ingest.irods_sync import add_arguments, handle_start, main, handle_watch, handle_stop, \
    handle_list

from irods_capability_automated_ingest.sync_actions import start_job, list_jobs, stop_job
from uuid import uuid1
from flask import Flask, request
import flask
from flask_restful import reqparse, Resource, Api
import click

import os
import argparse

app = Flask(__name__)

api = Api(app)

parser_start = reqparse.RequestParser()

class Jobs(Resource):

    def post(self):
        data = request.get_json()
        source = data["source"]
        target = data["target"]
        return_code = parse_args(["start", source, target, "--synchronous", "--ignore_cache", "--event_handler", "/var/lib/irods/event_handler.py", "--log_filename", "/tmp/daniel.log"])
        if return_code == 0:
            return {"success":True}, 200
        else:
            return {"success": False}, 500


api.add_resource(Jobs, "/job")

def get_config():
    return {
        "log": {
            "filename": os.environ.get("log_filename"),
            "when": os.environ.get("log_when"),
            "interval": os.environ.get("log_interval"),
            "level": os.environ.get("log_level")
        },
        "redis": {
            "host" : os.environ.get("redis_host", "localhost"),
            "port" : os.environ.get("redis_port", 6379),
            "db" : os.environ.get("redis_db", 0)
        }
    }


DEFAULT_EVENT_HANDLER_PATH = "/tmp"


builtin_run_command = flask.cli.run_command


@app.cli.command('run_app', help=builtin_run_command.help, short_help=builtin_run_command.short_help)
@click.option("--event_handler_path", default=DEFAULT_EVENT_HANDLER_PATH)
@click.pass_context
def run_app(ctx, event_handler_path, **kwargs):
    app.config["event_handler_path"] = event_handler_path
    ctx.params.pop("event_handler_path", None)
    ctx.forward(builtin_run_command)

run_app.params[:0] = builtin_run_command.params


def parse_args(args):
    parser = argparse.ArgumentParser(
        description='continuous synchronization utility')
    subparsers = parser.add_subparsers(help="subcommand help")

    parser_start = subparsers.add_parser(
        "start", formatter_class=argparse.ArgumentDefaultsHelpFormatter, help="start help")
    parser_start.add_argument('src_path', metavar='SOURCE_DIRECTORY',
                              type=str, help='Source directory or S3 folder to scan.')
    parser_start.add_argument('target', metavar='TARGET_COLLECTION', type=str,
                              help='Target iRODS collection for data objects (created if non-existent).')
    parser_start.add_argument('-i', '--interval', action="store", type=int, default=None,
                              help='Restart interval (in seconds). If absent, will only sync once.')
    parser_start.add_argument('--file_queue', action="store", type=str, default="file", help='Name for the file queue.')
    parser_start.add_argument('--path_queue', action="store", type=str, default="path", help='Name for the path queue.')
    parser_start.add_argument('--restart_queue', action="store", type=str, default="restart",
                              help='Name for the restart queue.')
    parser_start.add_argument('--event_handler', action="store",
                              type=str, default=None, help='Path to event handler file')
    parser_start.add_argument('--job_name', action="store", type=str, default=None,
                              help='Reference name for ingest job (defaults to generated uuid)')
    parser_start.add_argument('--append_json', action="store",
                              type=json.loads, default=None, help='Append json output')
    parser_start.add_argument("--ignore_cache", action="store_true", default=False,
                              help='Ignore last sync time in cache - like starting a new sync')
    parser_start.add_argument("--initial_ingest", action="store_true", default=False,
                              help='Use this flag on initial ingest to avoid check for data object paths already in iRODS.')
    parser_start.add_argument('--synchronous', action="store_true",
                              default=False, help='Block until sync job is completed.')
    parser_start.add_argument('--progress', action="store_true", default=False,
                              help='Show progress bar and task counts (must have --synchronous flag).')
    parser_start.add_argument('--profile', action="store_true", default=False,
                              help='Generate JSON file of system activity profile during ingest.')
    parser_start.add_argument('--files_per_task', action="store", type=int,
                              default='50', help='Number of paths to process in a given task on the queue.')
    parser_start.add_argument('--s3_endpoint_domain', action="store",
                              type=str, default='s3.amazonaws.com', help='S3 endpoint domain')
    parser_start.add_argument('--s3_region_name', action="store",
                              type=str, default='us-east-1', help='S3 region name')
    parser_start.add_argument('--s3_keypair', action="store",
                              type=str, default=None, help='Path to S3 keypair file')
    parser_start.add_argument('--s3_proxy_url', action="store",
                              type=str, default=None, help='URL to proxy for S3 access')
    parser_start.add_argument('--s3_insecure_connection', action="store_true",
                              default=False, help='Do not use SSL when connecting to S3 endpoint')
    parser_start.add_argument('--exclude_file_type', nargs=1, action="store", default='none',
                              help='types of files to exclude: regular, directory, character, block, socket, pipe, link')
    parser_start.add_argument('--exclude_file_name', type=list, nargs='+', action="store", default='none',
                              help='a list of space-separated python regular expressions defining the file names to exclude such as "(\S+)exclude" "(\S+)\.hidden"')
    parser_start.add_argument('--exclude_directory_name', type=list, nargs='+', action="store", default='none',
                              help='a list of space-separated python regular expressions defining the directory names to exclude such as "(\S+)exclude" "(\S+)\.hidden"')
    parser_start.add_argument('--irods_idle_disconnect_seconds', action="store",
                              type=int, default=60, help='irods disconnect time in seconds')
    add_arguments(parser_start)

    parser_start.set_defaults(func=handle_start)

    parser_stop = subparsers.add_parser(
        "stop", formatter_class=argparse.ArgumentDefaultsHelpFormatter, help="stop help")
    parser_stop.add_argument('job_name', action="store",
                             type=str, help='job name')
    add_arguments(parser_stop)
    parser_stop.set_defaults(func=handle_stop)

    parser_watch = subparsers.add_parser(
        "watch", formatter_class=argparse.ArgumentDefaultsHelpFormatter, help="watch help")
    parser_watch.add_argument(
        'job_name', action="store", type=str, help='job name')
    add_arguments(parser_watch)
    parser_watch.set_defaults(func=handle_watch)

    parser_list = subparsers.add_parser(
        "list", formatter_class=argparse.ArgumentDefaultsHelpFormatter, help="list help")
    add_arguments(parser_list)
    parser_list.set_defaults(func=handle_list)

    args = parser.parse_args(args=args)
    return args.func(args)
