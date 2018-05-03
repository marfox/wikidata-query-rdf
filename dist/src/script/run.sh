#!/usr/bin/env bash

###
# Start the Wikidata primary sources tool back end version 2.
#
# Default variable values apply to the deployment on a WMF VPS instance.
# -Project: https://tools.wmflabs.org/openstack-browser/project/wikidata-primary-sources-tool
# -Instance: https://tools.wmflabs.org/openstack-browser/server/pst.wikidata-primary-sources-tool.eqiad.wmflabs
# -Base URI: https://pst.wmflabs.org/v2
###

# Environment variables needed by the primary sources tool
# See https://tools.wmflabs.org/primary-sources-v2/javadoc/org/wikidata/query/rdf/primarysources/common/Config.html
# HOST, PORT, and CONTEXT are also used in this script
export HOST=${HOST:-"10.68.22.221"}
export PORT=${PORT:-"9999"}
export CONTEXT=${CONTEXT:-"v2"}
export ENTITIES_CACHE=`pwd`/entities_cache
export DATASETS_CACHE=`pwd`/datasets_stats.json
export CACHE_UPDATE_TIME_UNIT=HOURS
export CACHE_UPDATE_INITIAL_DELAY=1
export CACHE_UPDATE_INTERVAL=24

if [ ! -d ${ENTITIES_CACHE} ]; then
  mkdir ${ENTITIES_CACHE}
fi

WORK_DIR=${WORK_DIR:-`pwd`}
JAVA=${JAVA:-"/srv/backend/jdk1.8.0_162/jre/bin/java"}
HEAP_SIZE=${HEAP_SIZE:-"14G"}
MEMORY=${MEMORY:-"-Xms${HEAP_SIZE} -Xmx${HEAP_SIZE}"}
LOG_CONFIG=${LOG_CONFIG:-""}
LOG_DIR=${LOG_DIR:-"`pwd`/../logs"}
LOG_LEVEL=${LOG_LEVEL:-"info"}
GC_LOGS=${GC_LOGS:-"-Xloggc:${LOG_DIR}/garbage_collection/pst.%p-%t.log \
    -XX:+PrintGCDetails \
    -XX:+PrintGCDateStamps \
    -XX:+PrintGCTimeStamps \
    -XX:+PrintAdaptiveSizePolicy \
    -XX:+PrintReferenceGC \
    -XX:+PrintGCCause \
    -XX:+PrintGCApplicationStoppedTime \
    -XX:+PrintTenuringDistribution \
    -XX:+UnlockExperimentalVMOptions \
    -XX:G1NewSizePercent=20 \
    -XX:+ParallelRefProcEnabled \
    -XX:+UseGCLogFileRotation \
    -XX:NumberOfGCLogFiles=10 \
    -XX:GCLogFileSize=20M"}
BLAZEGRAPH_PROPS=${BLAZEGRAPH_PROPS:-"RWStore.properties"}

# Workaround to MemoryManagerOutOfMemory while executing queries.
# See https://sourceforge.net/p/bigdata/mailman/message/35380438/
# Does not seem to be effective anyway.
# Uncomment the following 2 lines to enable it.
#NATIVE_HEAP_SIZE=${NATIVE_HEAP_SIZE:-"14G"}
#MEMORY=${MEMORY:-"-Xms${HEAP_SIZE} -Xmx${HEAP_SIZE} -XX:MaxDirectMemorySize=${NATIVE_HEAP_SIZE}"}

# Uncomment the following line to enable the debugger
#DEBUGGER=-agentlib:jdwp=transport=dt_socket,server=y,address=8000,suspend=n

function usage() {
  printf "Usage: $0 [OPTIONS]\n \
    OPTIONS:\n \
    -j JAVA_EXECUTABLE   Path to a Java 8 executable. Default='/srv/backend/jdk1.8.0_162/jre/bin/java'\n \
    -m MEMORY            Amount of RAM for Java. Same for both initial and maximum heap size. Default='14G'\n \
    -h HOST              Host name or local IP where this service gets deployed. Default='10.68.22.221'\n \
    -p PORT              Port where this service gets deployed. Default='9999'\n \
    -c CONTEXT           Base path where this service gets deployed. Default='v2'\n \
    -b BLAZEGRAPH_PROPS  Java properties file with Blazegraph configuration. Default='./RWStore.properties'\n \
    -w WORK_DIR          Work directory. Default=current\n \
    -l LOG_DIR           Log files directory. Default='../logs'\n \
    -d                   Enable primary sources tool debug log messages. Default level=info\n \
    -?                   Show this help and exit.\n"
  exit 1
}

# Command line parsing
while getopts j:m:h:p:c:b:w:l:d? option
do
  case "${option}"
  in
    j) JAVA=${OPTARG};;
    m) HEAP_SIZE=${OPTARG};;
    h) HOST=${OPTARG};;
    p) PORT=${OPTARG};;
    c) CONTEXT=${OPTARG};;
    b) BLAZEGRAPH_PROPS=${OPTARG};;
    w) WORK_DIR=${OPTARG};;
    l) LOG_DIR=${OPTARG};;
    d) LOG_LEVEL="debug";;
    ?) usage;;
  esac
done

pushd ${WORK_DIR}

mkdir -p ${LOG_DIR}/garbage_collection
LOG_OPTIONS="-DlogLevel=${LOG_LEVEL} -DlogDir=${LOG_DIR}"
if [ "${LOG_CONFIG}" ]; then
  LOG_OPTIONS="${LOG_OPTIONS} -Dlogback.configurationFile=${LOG_CONFIG}"
fi

# Earth QID
DEFAULT_GLOBE=2
# HTTP user agent for federation
USER_AGENT="Wikidata primary sources tool; https://pst.wmflabs.org/v2";

# Uncomment the following command to output the script variables 
# echo "Script variables: Java=${JAVA} - memory=${HEAP_SIZE} - host=${HOST} \
#   - port=${PORT} - context=${CONTEXT} - blazegraph_properties=${BLAZEGRAPH_PROPS} \
#   - work_dir=${WORK_DIR} - log_dir=${LOG_DIR} - log_level=${LOG_LEVEL}"

printf "\nThe Wikidata primary sources tool will run from '${WORK_DIR}' on '${HOST}:${PORT}/${CONTEXT}'\n\n"

exec ${JAVA} \
    -server -XX:+UseG1GC ${MEMORY} ${DEBUGGER} ${GC_LOGS} ${LOG_OPTIONS} \
    -Dcom.bigdata.rdf.sail.webapp.ConfigParams.propertyFile=${BLAZEGRAPH_PROPS} \
    -Dorg.eclipse.jetty.server.Request.maxFormContentSize=200000000 \
    -Dcom.bigdata.rdf.sparql.ast.QueryHints.analytic=true \
    -Dcom.bigdata.rdf.sparql.ast.QueryHints.analyticMaxMemoryPerQuery=939524096 \
    -DASTOptimizerClass=org.wikidata.query.rdf.blazegraph.WikibaseOptimizers \
    -Dorg.wikidata.query.rdf.blazegraph.inline.literal.WKTSerializer.noGlobe=${DEFAULT_GLOBE} \
    -Dcom.bigdata.rdf.sail.webapp.client.RemoteRepository.maxRequestURLLength=7168 \
    -Dcom.bigdata.rdf.sail.sparql.PrefixDeclProcessor.additionalDeclsFile=${WORK_DIR}/prefixes.conf \
    -Dorg.wikidata.query.rdf.blazegraph.mwapi.MWApiServiceFactory.config=${WORK_DIR}/mwservices.json \
    -Dcom.bigdata.rdf.sail.webapp.client.HttpClientConfigurator=org.wikidata.query.rdf.blazegraph.ProxiedHttpConnectionFactory \
    -Dhttp.userAgent="${USER_AGENT}" \
    -jar jetty-runner*.jar \
    --host ${HOST} \
    --port ${PORT} \
    --path /${CONTEXT} \
    blazegraph-service-*.war
