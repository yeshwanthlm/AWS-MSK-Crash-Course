# AWS-MSK-Crash-Course
<img width="1920" height="1080" alt="AWS MSK Crash Course" src="https://github.com/user-attachments/assets/b216fdcb-c24a-4c79-ada1-e034707f7cc4" />

### Command to create a topic:
```bash
bin/kafka-topics.sh --create \
  --bootstrap-server <bootstrapServerString> \
  --command-config /home/ec2-user/kafka_2.13-3.6.0/bin/client.properties \
  --replication-factor 3 \
  --partitions 1 \
  --topic my-first-topic
```

### Command to produce the message to the topic my-first-topic
```bash
bin/kafka-console-producer.sh \
  --broker-list <bootstrapServerString> \
  --producer.config /home/ec2-user/kafka_2.13-3.6.0/bin/client.properties \
  --topic my-first-topic
```

### Command to consume from the message to the topic my-first-topic
```bash
bin/kafka-console-consumer.sh \
  --bootstrap-server <bootstrapServerString> \
  --consumer.config /home/ec2-user/kafka_2.13-3.6.0/bin/client.properties \
  --topic my-first-topic \
  --from-beginning
```
