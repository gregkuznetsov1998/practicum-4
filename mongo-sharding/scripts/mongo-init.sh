#!/bin/bash

###
# Инициализируем бд
###
echo "configSrv"
docker exec -t configSrv mongosh --port 27017 --eval '
rs.initiate(
  {
    _id : "config_server",
    configsvr: true,
    members: [
      { _id : 0, host : "configSrv:27017" }
    ]
  }
);
'

sleep 10

echo "shard1"
docker exec -t shard1 mongosh --port 27018 --eval '
rs.initiate(
    {
      _id : "shard1",
      members: [
        { _id : 0, host : "shard1:27018" }
      ]
    }
);
'

echo "shard2"
docker exec -t shard2 mongosh --port 27019 --eval '
rs.initiate(
    {
      _id : "shard2",
      members: [
        { _id : 0, host : "shard2:27019" }
      ]
    }
);
'

sleep 10

echo "mongos_router"
docker exec -t mongos_router mongosh --port 27020 --eval '
sh.addShard("shard1/shard1:27018");
sh.addShard("shard2/shard2:27019");
sh.enableSharding("somedb");
db = db.getSiblingDB("somedb");
db.createCollection("helloDoc");
sh.shardCollection("somedb.helloDoc", { _id: "hashed" });
'

sleep 5

echo "init"
docker exec -i mongos_router mongosh --port 27020 <<EOF
use somedb;
for (let i = 0; i < 1000; i++) {
    db.helloDoc.insertOne({age: i, name: "ly" + i});
}
EOF

sleep 5
echo "Initialization completed"