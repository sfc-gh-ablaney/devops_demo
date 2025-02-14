{% from 'modules/create_warehouse.jinja2' import create_warehouse-%}
{% from 'modules/create_database.jinja2' import create_database-%}
{% set env = '' if env_var("SNOWFLAKE_ENV").upper() in ['NOENV', 'PROD'] else '_' ~ env_var("SNOWFLAKE_ENV").upper()  %}
{% set env_base_prefix = env_var("SCHEMACHANGE_OBJ_PREFIX") %}
{% set owning_role = env_var("SCHEMACHANGE_OWNING_ROLE_FINAL") %}

-- list of warehouses
{% set env_whs = ['ADMIN', 'INGEST', 'PIPELINE', 'BI'] %}
{%- for wh in env_whs %}
{% set custom_properties = {"warehouse_size": "XSMALL"}%}
{% set wh_grants = {}%}
{% set rm_grants = {}%}
{{create_warehouse(env_var("SNOWFLAKE_ENV"), wh, custom_properties, wh_grants, rm_grants)}}
{%- endfor %}

-- list of dbs/schemas
{% set env_dbs = {'RAW': ['SOURCEA'], 
                  'COMMON': ['UTIL'], 
                  'ODS': ['STAGE', 'BASE'], 
                  'MDL': ['STAGE', 'BASE']} %}
{% set custom_properties = {}%}
{% set db_grants = {} %}
{% set sch_grants = {} %}
{%- for db, schemas in env_dbs.items() %}
{{create_database(env_var("SNOWFLAKE_ENV"), db, custom_properties, schemas, db_grants, sch_grants)}}
{%- endfor %} 