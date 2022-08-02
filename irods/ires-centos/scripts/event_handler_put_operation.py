from irods_capability_automated_ingest.core import Core
from irods_capability_automated_ingest.utils import Operation


class event_handler(Core):

    @staticmethod
    def max_retries(hdlr_mod, logger, meta):
        return 3

    @staticmethod
    def delay(hdlr_mod, logger, meta, retries):
        return 15

    @staticmethod
    def operation(session, meta, **options):
        return Operation.PUT
