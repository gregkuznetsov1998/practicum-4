#!/bin/bash

echo "Config server initialization"
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

until docker exec configSrv mongosh --port 27017 --eval "rs.status().ok" --quiet; do
  sleep 5
done
echo "Config server ready"

echo "Shard1 initialization"
docker exec -t shard1_primary mongosh --port 27018 --eval '
rs.initiate(
    {
      _id : "shard1",
      members: [
        { _id : 0, host : "shard1_primary:27018", priority: 3 },
        { _id : 1, host : "shard1_secondary1:27018", priority: 2 },
        { _id : 2, host : "shard1_secondary2:27018", priority: 1 }
      ]
    }
);
'

echo "Shard2 initialization"
docker exec -t shard2_primary mongosh --port 27019 --eval '
rs.initiate(
    {
      _id : "shard2",
      members: [
        { _id : 0, host : "shard2_primary:27019", priority: 3 },
        { _id : 1, host : "shard2_secondary1:27019", priority: 2 },
        { _id : 2, host : "shard2_secondary2:27019", priority: 1 }
      ]
    }
);
'

for shard in shard1_primary:27018 shard2_primary:27019; do
  until docker exec ${shard%:*} mongosh --port ${shard#*:} --eval "rs.status().ok && rs.status().members.find(m => m.state === 1)" --quiet; do
    sleep 5
  done
  echo "$shard ready"
done

echo "Mongos router configuration"
docker exec -t mongos_router mongosh --port 27020 --eval '
sh.addShard("shard1/shard1_primary:27018,shard1_secondary1:27018,shard1_secondary2:27018");
sh.addShard("shard2/shard2_primary:27019,shard2_secondary1:27019,shard2_secondary2:27019");
sh.enableSharding("somedb");

db = db.getSiblingDB("somedb");
db.createCollection("helloDoc");

sh.shardCollection("somedb.helloDoc", { _id: "hashed" });
'

until docker exec mongos_router mongosh --port 27020 --eval "sh.status().ok" --quiet; do
  sleep 5
done

echo "Inserting test data"
docker exec -i mongos_router mongosh --port 27020 <<EOF
use somedb;
for (let i = 0; i < 1000; i++) {
    db.helloDoc.insertOne({age: i, name: "ly" + i});
}
EOF

sleep 5
echo "Initialization completed"
