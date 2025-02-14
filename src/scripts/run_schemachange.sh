#!/bin/bash

set -e
set -o pipefail

echo "Environment variables:"
export SCHEMACHANGE_OBJ_PREFIX=`echo "${SCHEMACHANGE_BASE_PREFIX}_${SNOWFLAKE_ENV}" | tr '[:lower:]' '[:upper:]' | sed 's/_NOENV//' | sed 's/_PROD//'`
export SCHEMACHANGE_OWNING_ROLE_FINAL=${SCHEMACHANGE_OBJ_PREFIX}_${SCHEMACHANGE_OWNING_ROLE}
echo "GITHUB_NORKSPACE: ${GITHUB_WORKSPACE}"
echo "SNOWFLAKE_TENANT_CODE: ${SNOWFLAKE_TENANT_CODE}"
echo "SNOWFLAKE_ENV: ${SNOWFLAKE_ENV}"
echo "SCHEMACHANGE_BASE_PREFIX: ${SCHEMACHANGE_BASE_PREFIX}"
echo "SNOWFLAKE_ACCOUNT: ${SNOWFLAKE_ACCOUNT}"
echo "SCHEMACHANGE_USER: ${SCHEMACHANGE_USER}"
echo "SCHEMACHANGE_ROLE: ${SCHEMACHANGE_ROLE}"
echo "SCHEMACHANGE_WAREHOUSE: ${SCHEMACHANGE_WAREHOUSE}"
echo "SCHEMACHANGE_DATABASE: ${SCHEMACHANGE_DATABASE}"
echo "SCHEMACHANGE_SCHEMA: ${SCHEMACHANGE_SCHEMA}"
echo "SNOWFLAKE_PRIVATE_KEY_PATH: ${SNOWFLAKE_PRIVATE_KEY_PATH}"
echo "SCHEMACHANGE_DRY_RUN: ${SCHEMACHANGE_DRY_RUN}"
python3 --version

echo "Preparing private key"
echo "${SNOWFLAKE_PRIVATE_KEY}" | base64 -d > "${SNOWFLAKE_PRIVATE_KEY_PATH}"
echo "Private key prepared"

if [[ ! -z "${RUN_SCHEMACHANGE_INIT}" ]]; then
  echo "Running schemachange init"
  python3 src/scripts/init_schemachange.py --schemachange_db "${SCHEMACHANGE_DATABASE}"
  echo "Completed schemachange init"
fi
export BASE_SCHEMACHANGE_ROOT_FOLDER=${SCHEMACHANGE_ROOT_FOLDER}
echo "Schemachange root folder is ${SCHEMACHANGE_ROOT_FOLDER}" 
if [ -d "${SCHEMACHANGE_ROOT_FOLDER}" ] && [ ! -z "${RUN_PLATFORM_LEVEL}" ]; then
  echo "Creating temp root folder..."
  mkdir src/__schemachange_root
  echo "Copying account scripts from ${SCHEMACHANGE_ROOT_FOLDER}"
  cp -a ${SCHEMACHANGE_ROOT_FOLDER}/*.sql src/__schemachange_root
  echo "Completed copying scripts from ${SCHEMACHANGE_ROOT_FOLDER}"
  echo "Copying scripts from src/platform/${SNOWFLAKE_ACCOUNT_NAME}"
  echo find src/platform/${SNOWFLAKE_ACCOUNT_NAME}/ -maxdepth 1 -type f -exec cp {} src/__schemachange_root \;
  export SCHEMACHANGE_ROOT_FOLDER=src/__schemachange_root
  echo "Running account specific script - dry run is ${SCHEMACHANGE_DRY_RUN}" 
  echo "Files in folder: `ls -ltr src/__schemachange_root/*.sql`"
  schemachange --config-folder ./cfg ${SCHEMACHANGE_DRY_RUN} ${SCHEMACHANGE_VERBOSE} > src/__schemachange_root/schemachange.log
  cat src/__schemachange_root/schemachange.log  
  export __MAX_APPLIED_TS_RAW=`grep "Max applied change script version: " src/__schemachange_root/schemachange.log | sed "s/Max applied change script version: //"`
  export __MAX_APPLIED_TS=`echo ${__MAX_APPLIED_TS_RAW} | sed "s/\.//g"`
  echo "The max applied date is ${__MAX_APPLIED_TS}"
  if [ -z "${__MAX_APPLIED_TS}" ]; then
      export __MAX_APPLIED_TS=1900010101
  else 
      export __LATEST_COMMIT_FILE=`ls src/__schemachange_root/V*${__MAX_APPLIED_TS_RAW}__*.sql | sed "s#src\/__schemachange_root#${BASE_SCHEMACHANGE_ROOT_FOLDER}#"`
      export __LATEST_COMMIT_TS=`git log -1 --date=format:'%Y%m%d%H%M%S'  --pretty="format:%cd" ${__LATEST_COMMIT_FILE}`
      echo "The latest file commit for ${__LATEST_COMMIT_FILE} is ${__LATEST_COMMIT_TS}"
  fi 
  for file in `ls src/__schemachange_root/*.sql`
  do
    export __ORIG_FILE=`echo ${file} | sed "s#src\/__schemachange_root#${BASE_SCHEMACHANGE_ROOT_FOLDER}#"`
    echo "Get the git changed date for ${__ORIG_FILE}"
    export __FILE_COMMIT_TS=`git log -1 --date=format:'%Y%m%d%H%M%S'  --pretty="format:%cd" ${__ORIG_FILE}`
    echo "The file commit timestamp is ${__FILE_COMMIT_TS}"
    export filedate=`echo $file | cut -d \/ -f 3 | cut -d _ -f 1 | sed "s/[ \.V]//g"`
    echo "Checking the file date for ${file} - the file date is ${filedate} and and has a commit timestamp of ${__FILE_COMMIT_TS}; the max applied date is ${__MAX_APPLIED_TS} with a commit date of ${__LATEST_COMMIT_TS}"
    if [[ ! -z "${__MAX_APPLIED_TS}" && ! -z "${__LATEST_COMMIT_TS}"  && ! -z "${__FILE_COMMIT_TS}" && ! -z "${filedate}" && "${filedate}" -le "${__MAX_APPLIED_TS}" && "${__FILE_COMMIT_TS}" -gt "${__LATEST_COMMIT_TS}" ]]; then
      export __ERROR="${file} was modified (${__LATEST_COMMIT_TS}) after the commit date for the most recently applied script ${__LATEST_COMMIT_TS} but has a file date of ${filedate} which is on/before the Max applied change script of ${__MAX_APPLIED_TS}"
      echo $__ERROR
      export __SCRIPT_VERSION_ERROR="${__SCRIPT_VERSION_ERROR}\n${__ERROR}"
    fi
  done     
  if [ ! -z  "${__SCRIPT_VERSION_ERROR}" ]; then
    echo "ERROR - ${__SCRIPT_VERSION_ERROR}"
    echo `ls -ltr src/__schemachange_root/*.sql`
    if [ "${SCHEMACHANGE_DRY_RUN}" == "--dry-run" ]; then
      exit -1
    fi
  fi
  echo "Schemachange completed executing scripts from ${SCHEMACHANGE_ROOT_FOLDER}"
elif [ -d "${SCHEMACHANGE_ROOT_FOLDER}" ] && [ -z "${RUN_PLATFORM_LEVEL}" ]; then
  echo "Copying env scripts from ${SCHEMACHANGE_ROOT_FOLDER} for env ${SNOWFLAKE_ENV}"
  mkdir src/__schemachange_root
  cp -a ${SCHEMACHANGE_ROOT_FOLDER}/*.sql src/__schemachange_root
  echo "Folder details: `ls -ltr  ${SCHEMACHANGE_ROOT_FOLDER}/*.sql `"
  echo "Completed copying scripts from ${SCHEMACHANGE_ROOT_FOLDER}"
  export SCHEMACHANGE_ROOT_FOLDER=src/__schemachange_root
  echo "Running ${SNOWFLAKE_ENV} specific scripts - dry run is ${SCHEMACHANGE_DRY_RUN}" 
  echo "Files in folder: `ls -ltr src/__schemachange_root/*.sql`"
  schemachange --config-folder ./cfg ${SCHEMACHANGE_DRY_RUN} ${SCHEMACHANGE_VERBOSE}  > src/__schemachange_root/schemachange.log
  cat src/__schemachange_root/schemachange.log 
  export __MAX_APPLIED_TS_RAW=`grep "Max applied change script version: " src/__schemachange_root/schemachange.log | sed "s/Max applied change script version: //"`
  export __MAX_APPLIED_TS=`echo ${__MAX_APPLIED_TS_RAW} | sed "s/\.//g"`
  echo "The max applied date is ${__MAX_APPLIED_TS}"
  if [ -z "${__MAX_APPLIED_TS}" ]; then
      export __MAX_APPLIED_TS=1900010101
  else 
      export __LATEST_COMMIT_FILE=`ls src/__schemachange_root/V*${__MAX_APPLIED_TS_RAW}__*.sql | sed "s#src\/__schemachange_root#${BASE_SCHEMACHANGE_ROOT_FOLDER}#"`
      export __LATEST_COMMIT_TS=`git log -1 --date=format:'%Y%m%d%H%M%S'  --pretty="format:%cd" ${__LATEST_COMMIT_FILE}`
      echo "The latest file commit for ${__LATEST_COMMIT_FILE} is ${__LATEST_COMMIT_TS}"
  fi 
  for file in `ls src/__schemachange_root/*.sql`
  do
    export __ORIG_FILE=`echo ${file} | sed "s#src\/__schemachange_root#${BASE_SCHEMACHANGE_ROOT_FOLDER}#"`
    echo "Get the git changed date for ${__ORIG_FILE}"
    export __FILE_COMMIT_TS=`git log -1 --date=format:'%Y%m%d%H%M%S'  --pretty="format:%cd" ${__ORIG_FILE}`
    echo "The file commit timestamp is ${__FILE_COMMIT_TS}"
    export filedate=`echo $file | cut -d \/ -f 3 | cut -d _ -f 1 | sed "s/[ \.V]//g"`
    echo "Checking the file date for ${file} - the file date is ${filedate} and and has a commit timestamp of ${__FILE_COMMIT_TS}; the max applied date is ${__MAX_APPLIED_TS} with a commit date of ${__LATEST_COMMIT_TS}"
    if [[ ! -z "${__MAX_APPLIED_TS}" && ! -z "${__LATEST_COMMIT_TS}"  && ! -z "${__FILE_COMMIT_TS}" && ! -z "${filedate}" && "${filedate}" -le "${__MAX_APPLIED_TS}" && "${__FILE_COMMIT_TS}" -gt "${__LATEST_COMMIT_TS}" ]]; then
      export __ERROR="${file} was modified (${__LATEST_COMMIT_TS}) after the commit date for the most recently applied script ${__LATEST_COMMIT_TS} but has a file date of ${filedate} which is on/before the Max applied change script of ${__MAX_APPLIED_TS}"
      echo $__ERROR
      export __SCRIPT_VERSION_ERROR="${__SCRIPT_VERSION_ERROR}\n${__ERROR}"
    fi
  done     
  if [ ! -z  "${__SCRIPT_VERSION_ERROR}" ]; then
    echo "ERROR - ${__SCRIPT_VERSION_ERROR}"
    echo `ls -ltr src/__schemachange_root/*.sql`
    if [ "${SCHEMACHANGE_DRY_RUN}" == "--dry-run" ]; then
      exit -1
    fi
  fi
  echo "Schemachange completed executing environment scripts from ${SCHEMACHANGE_ROOT_FOLDER}"
  export BASE_SCHEMACHANGE_TABLE=${SCHEMACHANGE_TABLE}
  echo "Processing env scripts from ${SCHEMACHANGE_ROOT_FOLDER} for env ${SNOWFLAKE_ENV}"
  for obj in 'warehouses' 'databases' 'grants'; do
    if [ -d src/${obj} ]; then
      echo "Executing scripts in src/${obj}"
      for fld in `find src/${obj} -type d | sort -u`; do
        echo "Running ${obj} specific scripts for ${SNOWFLAKE_ENV} in ${fld}"
        fld_fmt=`echo $fld | tr '\/' '_' | tr '[:lower:]' '[:upper:]'`
        if [ `ls ${fld}/*.sql | wc -l` -gt 0 ]; then
          echo "Cleaning up temp root folder..."
          if [ -d src/__schemachange_root ]; then
            rm -rf src/__schemachange_root
          fi
          echo "Creating temp root folder..."
          mkdir src/__schemachange_root
          echo "Copying ${obj} scripts from ${fld} into temp schemachange root folder"
          export BASE_SCHEMACHANGE_ROOT_FOLDER=${fld}
          cp -a ${fld}/*.sql src/__schemachange_root
          export SCHEMACHANGE_TABLE=${BASE_SCHEMACHANGE_TABLE}_${fld_fmt}
          echo "Running ${obj} specific scripts for ${SNOWFLAKE_ENV} using change tracking table ${SCHEMACHANGE_TABLE} - Dry-run is  ${SCHEMACHANGE_DRY_RUN}" 
          echo "Files in folder: `ls -ltr src/__schemachange_root/*.sql`"
          schemachange --config-folder ./cfg ${SCHEMACHANGE_DRY_RUN} ${SCHEMACHANGE_VERBOSE} > src/__schemachange_root/schemachange.log
          cat src/__schemachange_root/schemachange.log
          export __MAX_APPLIED_TS_RAW=`grep "Max applied change script version: " src/__schemachange_root/schemachange.log | sed "s/Max applied change script version: //"`
          export __MAX_APPLIED_TS=`echo ${__MAX_APPLIED_TS_RAW} | sed "s/\.//g"`
          echo "The max applied date is ${__MAX_APPLIED_TS}"
          if [ -z "${__MAX_APPLIED_TS}" ]; then
            export __MAX_APPLIED_TS=1900010101
          else 
            export __LATEST_COMMIT_FILE=`ls src/__schemachange_root/V*${__MAX_APPLIED_TS_RAW}__*.sql | sed "s#src\/__schemachange_root#${BASE_SCHEMACHANGE_ROOT_FOLDER}#"`
            export __LATEST_COMMIT_TS=`git log -1 --date=format:'%Y%m%d%H%M%S'  --pretty="format:%cd" ${__LATEST_COMMIT_FILE}`
            echo "The latest file commit for ${__LATEST_COMMIT_FILE} is ${__LATEST_COMMIT_TS}"
          fi 
          for file in `ls src/__schemachange_root/*.sql`
          do
            export __ORIG_FILE=`echo ${file} | sed "s#src\/__schemachange_root#${BASE_SCHEMACHANGE_ROOT_FOLDER}#"`
            echo "Get the git changed date for ${__ORIG_FILE}"
            export __FILE_COMMIT_TS=`git log -1 --date=format:'%Y%m%d%H%M%S'  --pretty="format:%cd" ${__ORIG_FILE}`
            echo "The file commit timestamp is ${__FILE_COMMIT_TS}"
            export filedate=`echo $file | cut -d \/ -f 3 | cut -d _ -f 1 | sed "s/[ \.V]//g"`
            echo "Checking the file date for ${file} - the file date is ${filedate} and and has a commit timestamp of ${__FILE_COMMIT_TS}; the max applied date is ${__MAX_APPLIED_TS} with a commit date of ${__LATEST_COMMIT_TS}"
            if [[ ! -z "${__MAX_APPLIED_TS}" && ! -z "${__LATEST_COMMIT_TS}"  && ! -z "${__FILE_COMMIT_TS}" && ! -z "${filedate}" && "${filedate}" -le "${__MAX_APPLIED_TS}" && "${__FILE_COMMIT_TS}" -gt "${__LATEST_COMMIT_TS}" ]]; then
              export __ERROR="${file} was modified (${__LATEST_COMMIT_TS}) after the commit date for the most recently applied script ${__LATEST_COMMIT_TS} but has a file date of ${filedate} which is on/before the Max applied change script of ${__MAX_APPLIED_TS}"
              echo $__ERROR
              export __SCRIPT_VERSION_ERROR="${__SCRIPT_VERSION_ERROR}\n${__ERROR}"
            fi
          done     
          if [ ! -z  "${__SCRIPT_VERSION_ERROR}" ]; then
            echo "ERROR - ${__SCRIPT_VERSION_ERROR}"
            echo `ls -ltr src/__schemachange_root/*.sql`
            if [ "${SCHEMACHANGE_DRY_RUN}" == "--dry-run" ]; then
              exit -1
            fi
          fi
          echo "Removing temp root folder..."
          rm -rf src/__schemachange_root
        else
          echo "No sql scripts found in ${fld}/*.sql"
        fi
      done
    else
      echo "No scripts found in src/${obj}"
    fi
  done
else 
  echo "Skipping schemachange - root folder ${SCHEMACHANGE_ROOT_FOLDER} does not exist" 
fi
echo "Final cleanup of temp root folder..."
if [ -d src/__schemachange_root ]; then
  rm -rf src/__schemachange_root
fi