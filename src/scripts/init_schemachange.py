# Logging including the timestamp, thread and the source code location
import logging
import argparse
import snowflake.connector
import os
from snowflake.connector.secret_detector import SecretDetector
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.asymmetric import dsa
from cryptography.hazmat.primitives import serialization

help_text = """This script initializes the schema_change database

Sample usage:
    python schemachange_init.py --schemachange_db TENANT_COMMON_DB --schemachange-wh TENANT_ADMIN_WH """

parser = argparse.ArgumentParser(prog="schemachange_init.py", usage='%(prog)s [options]', description=help_text)
parser.add_argument('--account', action='store', help='Snowflake account locator MINUS snowflakecomputing.com')
parser.add_argument('--warehouse', action='store', help='Snowflake warehouse')
parser.add_argument('--role', action='store', help='Snowflake role')
parser.add_argument('--database', action='store', help='Snowflake database, i.e. where the stage resides')
parser.add_argument('--schema', action='store', help='Snowflake schema, i.e. where the stage resides')
parser.add_argument('--user action="store', help='Snowflake user')
parser.add_argument('--private_key', action='store', help='Snowflake private key location - PLEASE pass as an environment variable')
parser.add_argument('--private_key_passphrase', action='store', help= 'Snowflake private key passphrase - PLEASE pass as an environment variable')
parser.add_argument('--schemachange_db', action='store', help='Schemachange target database')
parser.add_argument('--schemachange_wh', action='store', help='Schemachange target warehouse')
parser.add_argument('--logfile', default='schemachange_init.log', action='store', help='Log file location, relative or fully qualified')
parser.add_argument('--tenant_code', default='DEMO', action='store', help='Short for the tenant')
parser.add_argument('--admin_namespace', default='ADMIN_SELF_SERVICE_NAMESPACE.SELF_SERVICE', action='store', help='Platform Admin Database util home')

# Set connection variables
args = parser.parse_args()
account=args.account if "SNOWFLAKE_ACCOUNT" not in os.environ else os.environ["SNOWFLAKE_ACCOUNT"]
user=args.user if "SCHEMACHANGE_USER" not in os.environ else os.environ["SCHEMACHANGE_USER"]
private_key_passphrase=os.environ["SNOWFLAKE_PRIVATE_KEY_PASSPHRASE"]
private_key=args.private_key if "SNOWFLAKE_PRIVATE_KEY_PATH" not in os.environ else os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"]
role=args.role if "SCHEMACHANGE_ROLE" not in os.environ else os.environ["SCHEMACHANGE_ROLE"]
database=args.database
schema=args.schema
warehouse=args.warehouse if "SCHEMACHANGE_WAREHOUSE" not in os.environ else os.environ["SCHEMACHANGE_WAREHOUSE"]
schemachange_db=args.schemachange_db
schemachange_wh=args.schemachange_wh
logfile=args.logfile
tenant_code=args.tenant_code if "SNOWFLAKE_TENANT_CODE" not in os.environ else os.environ["SNOWFLAKE_TENANT_CODE"]
admin_namespace=args.admin_namespace if "ADMIN_SELF_SERVICE_NAMESPACE" not in os.environ else os.environ["ADMIN_SELF_SERVICE_NAMESPACE"]
warehouse=f"{tenant_code}_{warehouse}"
role=f"{tenant_code}_{role}"

logger=None
for logger_name in ['snowflake.connector']:
    logger=logging.getLogger(logger_name)
    logger.setLevel(logging.INFO)
    ch=logging.StreamHandler ()
    ch.setLevel(logging.INFO)
    ch.setFormatter (SecretDetector('%(asctime)s - %(threadName)s - %(filename)s:%(lineno)d - %(funcName)s() %(levelname)s - %(message)s'))
    logger.addHandler(ch)
    ch = logging.FileHandler(f"{logfile}")
    ch.setFormatter (SecretDetector('%(asctime)s - %(threadName)s - %(filename)s:%(lineno)d - %(funcName)s() %(levelname)s - %(message)s'))
    ch.setLevel(logging.INFO)
    logger.addHandler(ch)

def get_connection_config():
    # Set options below
    sfOptions = {"account" : account,
    "user" : user,
    "database": database,
    "schema" : schema,
    "role" : role,
    "warehouse" : warehouse,
    }
    return sfOptions

def get_connection (get_connection_config):
    try:
        with open(private_key, "rb") as key:
            p_key= serialization. load_pem_private_key(
                key.read(),
                password=private_key_passphrase.encode(),
                backend=default_backend()
            )
            pkb = p_key.private_bytes(
                encoding=serialization.Encoding.DER,
                format=serialization.PrivateFormat.PKCS8,
                encryption_algorithm=serialization.NoEncryption())

            logger.info(f"Connecting to Snowflake using account = {get_connection_config['account']} \
                user = {get_connection_config['user']} \
                warehouse = {get_connection_config['warehouse']} \
                role = {get_connection_config['role']} \
                database = {get_connection_config['database']} \
                schema = {get_connection_config['schema']}")

            my_cnx = snowflake.connector.connect(
                user=get_connection_config['user'],
                account=get_connection_config['account'],
                warehouse=get_connection_config['warehouse'],
                database=get_connection_config['database'],
                schema=get_connection_config['schema'],
                role=get_connection_config['role'],
                private_key=pkb
            )

    except ValueError as e:
        logger.error(f"Error when getting connection to account {get_connection_config['account']}")
        raise Exception(f"Error when getting connection to account {get_connection_config['account']}")
    return my_cnx

try:
    logger.info(f'Connecting to account {account}')
    conn= get_connection(get_connection_config())
    qrycur = conn.cursor()
    logger.info(f'Creating Schemachange database {schemachange_db}')
    schemachange_db_and_publicschema = f"{schemachange_db}.PUBLIC"
    schemachange_db_and_schemachangeschema = f"{schemachange_db}.SCHEMACHANGE"
    df = qrycur.execute( "create database if not exists identifier(%s)", (schemachange_db))
    df = qrycur.execute( "drop schema if exists identifier(%s)", (schemachange_db_and_publicschema))
    df = qrycur.execute( "create schema if not exists identifier(%s) with managed access", (schemachange_db_and_schemachangeschema))
    logger.info(f'Complete!')
except ValueError as e:
    logger.error(f'Error!!!!')
    raise Exception(f'Error!!!!')