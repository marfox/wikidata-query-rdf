#!/usr/bin/env bash

if [ -r /etc/default/wdqs-blazegraph ]; then
  . /etc/default/wdqs-blazegraph
fi

# Environment variables needed by the primary sources tool
# See https://tools.wmflabs.org/primary-sources-v2/javadoc/org/wikidata/query/rdf/primarysources/common/Config.html
# HOST, PORT, and CONTEXT are also used in this script
export HOST=${HOST:-"10.68.22.221"}
export PORT=${PORT:-"9999"}
export CONTEXT=${CONTEXT:-"v2"}
export ENTITIES_CACHE=$(pwd)/entities_cache
export DATASETS_CACHE=$(pwd)/datasets_stats.json
export CACHE_UPDATE_TIME_UNIT=HOURS
export CACHE_UPDATE_INITIAL_DELAY=1
export CACHE_UPDATE_INTERVAL=24

if [ ! -d $ENTITIES_CACHE ]; then
  mkdir $ENTITIES_CACHE
fi

DIR=${DIR:-`dirname $0`}
JAVA=${JAVA:-"/srv/backend/jdk1.8.0_162/jre/bin/java"}
HEAP_SIZE=${HEAP_SIZE:-"14G"}
LOG_CONFIG=${LOG_CONFIG:-""}
GC_LOG_DIR=${LOG_DIR:-"$(pwd)/../gc_logs"}
MEMORY=${MEMORY:-"-Xms${HEAP_SIZE} -Xmx${HEAP_SIZE}"}
# Workaround to MemoryManagerOutOfMemory while executing queries
# See https://sourceforge.net/p/bigdata/mailman/message/35380438/
# Does not seem to be effective anyway
# Uncomment the following 2 lines to enable it
#NATIVE_HEAP_SIZE=${NATIVE_HEAP_SIZE:-"14G"}
#MEMORY=${MEMORY:-"-Xms${HEAP_SIZE} -Xmx${HEAP_SIZE} -XX:MaxDirectMemorySize=${NATIVE_HEAP_SIZE}"}
GC_LOGS=${GC_LOGS:-"-Xloggc:${GC_LOG_DIR}/pst.%p-%t.log \
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
EXTRA_JVM_OPTS=${EXTRA_JVM_OPTS:-""}
BLAZEGRAPH_OPTS=${BLAZEGRAPH_OPTS:-""}
CONFIG_FILE=${CONFIG_FILE:-"RWStore.properties"}
# Uncomment the following line for debugging
#DEBUG=-agentlib:jdwp=transport=dt_socket,server=y,address=8000,suspend=n

function usage() {
  echo "Usage: $0 [-j <java 8 executable>] [-h <host>] [-p <port>] [-c <context>] [-d <working dir>] [-o <blazegraph options>] [-f RWStore.properties]"
  exit 1
}

while getopts j:h:c:p:d:o:f:? option
do
  case "${option}"
  in
    j) JAVA=${OPTARG};;
    h) HOST=${OPTARG};;
    c) CONTEXT=${OPTARG};;
    p) PORT=${OPTARG};;
    d) DIR=${OPTARG};;
    o) BLAZEGRAPH_OPTS="${OPTARG}";;
    f) CONFIG_FILE=${OPTARG};;
    ?) usage;;
  esac
done

pushd $DIR

# Earth QID
DEFAULT_GLOBE=2
# Blazegraph HTTP User Agent for federation
USER_AGENT="Wikidata primary sources tool; https://pst.wmflabs.org/v2";

if [ ! -d $LOG_DIR ]; then
  mkdir $LOG_DIR
fi

if [ "$LOG_CONFIG" ]; then
  LOG_OPTIONS="-Dlogback.configurationFile=${LOG_CONFIG}"
fi

echo "Running Blazegraph from `pwd` on $HOST:$PORT/$CONTEXT"
exec ${JAVA} \
    -server -XX:+UseG1GC ${MEMORY} ${DEBUG} ${GC_LOGS} ${LOG_OPTIONS} ${EXTRA_JVM_OPTS} \
    -Dcom.bigdata.rdf.sail.webapp.ConfigParams.propertyFile=${CONFIG_FILE} \
    -Dorg.eclipse.jetty.server.Request.maxFormContentSize=200000000 \
    -Dcom.bigdata.rdf.sparql.ast.QueryHints.analytic=true \
    -Dcom.bigdata.rdf.sparql.ast.QueryHints.analyticMaxMemoryPerQuery=939524096 \
    -DASTOptimizerClass=org.wikidata.query.rdf.blazegraph.WikibaseOptimizers \
    -Dorg.wikidata.query.rdf.blazegraph.inline.literal.WKTSerializer.noGlobe=$DEFAULT_GLOBE \
    -Dcom.bigdata.rdf.sail.webapp.client.RemoteRepository.maxRequestURLLength=7168 \
    -Dcom.bigdata.rdf.sail.sparql.PrefixDeclProcessor.additionalDeclsFile=$DIR/prefixes.conf \
    -Dorg.wikidata.query.rdf.blazegraph.mwapi.MWApiServiceFactory.config=$DIR/mwservices.json \
    -Dcom.bigdata.rdf.sail.webapp.client.HttpClientConfigurator=org.wikidata.query.rdf.blazegraph.ProxiedHttpConnectionFactory \
    -Dhttp.userAgent="${USER_AGENT}" \
    ${BLAZEGRAPH_OPTS} \
    -jar jetty-runner*.jar \
    --host $HOST \
    --port $PORT \
    --path /$CONTEXT \
    blazegraph-service-*.war

