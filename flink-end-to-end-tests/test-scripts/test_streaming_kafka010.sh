#!/usr/bin/env bash
################################################################################
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
################################################################################

source "$(dirname "$0")"/common.sh
source "$(dirname "$0")"/kafka-common.sh

setup_kafka_dist
start_kafka_cluster

# modify configuration to have enough slots
cp $FLINK_DIR/conf/flink-conf.yaml $FLINK_DIR/conf/flink-conf.yaml.bak
sed -i -e "s/taskmanager.numberOfTaskSlots: 1/taskmanager.numberOfTaskSlots: 3/" $FLINK_DIR/conf/flink-conf.yaml

start_cluster

function test_cleanup {
  stop_kafka_cluster

  # revert our modifications to the Flink distribution
  rm $FLINK_DIR/conf/flink-conf.yaml
  mv $FLINK_DIR/conf/flink-conf.yaml.bak $FLINK_DIR/conf/flink-conf.yaml

  # make sure to run regular cleanup as well
  cleanup
}
trap test_cleanup INT
trap test_cleanup EXIT

# create the required topics
create_kafka_topic 1 1 test-input
create_kafka_topic 1 1 test-output

# run the Flink job (detached mode)
$FLINK_DIR/bin/flink run -d $FLINK_DIR/examples/streaming/Kafka010Example.jar \
  --input-topic test-input --output-topic test-output \
  --prefix=PREFIX \
  --bootstrap.servers localhost:9092 --zookeeper.connect localhost:2181 --group.id myconsumer --auto.offset.reset earliest

function verify_output {
  local expected=$(printf $1)

  if [[ "$2" != "$expected" ]]; then
    echo "Output from Flink program does not match expected output."
    echo -e "EXPECTED FOR KEY: --$expected--"
    echo -e "ACTUAL: --$2--"
    PASS=""
    exit 1
  fi
}

# send some data to Kafka
send_messages_to_kafka "elephant,5,45218\nsquirrel,12,46213\nbee,3,51348\nsquirrel,22,52444\nbee,10,53412\nelephant,9,54867" test-input
KEY_1_MSGS=$(read_messages_from_kafka 6 test-output | grep elephant)
KEY_2_MSGS=$(read_messages_from_kafka 6 test-output | grep squirrel)
KEY_3_MSGS=$(read_messages_from_kafka 6 test-output | grep bee)

# check all keys; make sure we have actual newlines in the string, not "\n"
verify_output "elephant,5,45218\nelephant,14,54867" "$KEY_1_MSGS"
verify_output "squirrel,12,46213\nsquirrel,34,52444" "$KEY_2_MSGS"
verify_output "bee,3,51348\nbee,13,53412" "$KEY_3_MSGS"
