sh.addShard("shard1/shard1:27018");
sh.addShard("shard2/shard2:27019");
sh.enableSharding("somedb")

use somedb;
db.createCollection("helloDoc");

sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { _id: "hashed" });