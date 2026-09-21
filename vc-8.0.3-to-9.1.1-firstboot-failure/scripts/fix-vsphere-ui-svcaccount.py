#!/bin/python3
import os
import sys
import logging
sys.path.append(os.environ['VMWARE_PYTHON_PATH'])
from cis.svcaccount_prestart_util import is_valid_account, setup_service_account
from cis.utils import setupLogging
setupLogging("fix_vsphere_ui_svcaccount", logMechanism="file")
logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.CRITICAL)
H5_CLIENT_SERVICE_ACCOUNT_NAME = 'vsphere-ui'
setup_service_account(H5_CLIENT_SERVICE_ACCOUNT_NAME)
if is_valid_account(H5_CLIENT_SERVICE_ACCOUNT_NAME):
    print("Successfully fixed the vsphere-ui service account")
else:
    print("Failed to fix the vsphere-ui service account")
