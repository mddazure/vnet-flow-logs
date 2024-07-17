---
title: Manage VNet Flow Logs using Grafana
titleSuffix: Azure Network Watcher
description: Manage and analyze virtual network flow logs in Azure using Network Watcher and Grafana.
services: network-watcher
author: halkazwini
tags: azure-resource-manager
ms.service: network-watcher
ms.topic: how-to
ms.workload: infrastructure-services
ms.date: 09/15/2022
ms.author: halkazwini
ms.custom: engagement-fy23
---
# Manage and analyze virtual network flow logs using Network Watcher and Grafana

[Virtual Network (VNet) flow logs](vnet-flow-logs-overview.md) provide information that can be used to understand ingress and egress IP traffic on network interfaces. These flow logs show outbound and inbound flows on a per NSG rule basis, the NIC the flow applies to, 5-tuple information about the flow (Source/Destination IP, Source/Destination Port, Protocol), and if the traffic was allowed or denied.

You can have many VNets in your network with flow logging enabled. This amount of logging data makes it cumbersome to parse and gain insights from your logs. This article provides a solution to centrally manage these VNet flow logs using Grafana, an open source graphing tool, ElasticSearch, a distributed search and analytics engine, and Logstash, which is an open source server-side data processing pipeline.  

## Scenario

VNet flow logs are enabled using Network Watcher and are stored in Azure blob storage. A Logstash plugin is used to connect and process flow logs from blob storage and send them to ElasticSearch.  Once the flow logs are stored in ElasticSearch, they can be analyzed and visualized into customized dashboards in Grafana.

![VNet Network Watcher Grafana][1]

## Installation steps

### Enable Virtual Network flow logging

For this scenario, you must have Virtual Network Flow Logging enabled on at least one Virtual Network in your account. For instructions on enabling Virtual Network Flow Logs, refer to the following article [Introduction to flow logging for Virtual Networks](vnet-flow-logs-overview.md).

### Setup considerations

In this example Grafana, ElasticSearch, and Logstash are configured on an Ubuntu 22.04 LTS Server deployed in Azure. This minimal setup is used for running all three components – they are all running on the same VM. This setup should only be used for testing and non-critical workloads. Logstash, Elasticsearch, and Grafana can all be architected to scale independently across many instances. For more information, see the documentation for each of these components.

### Install Elasticsearch

1. The Elastic Stack version 8.0 requires Java 8. Run the command `java -version` to check your version. If you do not have Java installed, refer to documentation on the [Azure-suppored JDKs](/azure/developer/java/fundamentals/java-support-on-azure).
   - To install OpenJDK 8, run the following command:
     ```bash
     sudo apt-get install openjdk-8-jdk
     ```
     You can confirm that the installation was successful by checking the Java version:
     ```bash
     java --version
     ```

2. Download the correct binary package for your system. The following commands are to download and install the Linux archive for ElasticSearch v8.8.2:

   ```bash
   wget https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-8.8.2-linux-x86_64.tar.gz
   wget https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-8.8.2-linux-x86_64.tar.gz.sha512
   shasum -a 512 -c elasticsearch-8.8.2-linux-x86_64.tar.gz.sha512 
   tar -xzf elasticsearch-8.8.2-linux-x86_64.tar.gz
   cd elasticsearch-8.8.2/ 
   ./bin/elasticsearch
   ```

   ElasticSearch v8 launches with security features configured by default. You should see a message after starting ElasticSearch displaying the initial security configuration:

   ```bash
   ✅ Elasticsearch security features have been automatically configured!
   ✅ Authentication is enabled and cluster connections are encrypted.

   ℹ️  Password for the elastic user (reset with `bin/elasticsearch-reset-password -u elastic`):
     <password>

   ℹ️  HTTP CA certificate SHA-256 fingerprint:
     <certificate-fingerprint>

   ℹ️  Configure Kibana to use this cluster:
   • Run Kibana and click the configuration link in the terminal when Kibana starts.
   • Copy the following enrollment token and paste it into Kibana in your browser (valid for the next 30 minutes):
     <kibana-enrollment-token>

   ℹ️  Configure other nodes to join this cluster:
   • On this node:
     ⁃ Create an enrollment token with `bin/elasticsearch-create-enrollment-token -s node`.
     ⁃ Uncomment the transport.host setting at the end of config/elasticsearch.yml.
     ⁃ Restart Elasticsearch.
   • On other nodes:
     ⁃ Start Elasticsearch with `bin/elasticsearch --enrollment-token <token>`, using the enrollment token that you generated.
   ```   

   -  To run ElasticSearch as a daemon, you can instead use the following command:

      ```bash
      ./bin/elasticsearch -d -p pid
      ```

      To stop the ElasticSearch daemon process:

      ```bash
      pkill -F pid
      ```

   Other installation methods can be found at [Elasticsearch Installation](https://www.elastic.co/guide/en/elasticsearch/reference/8.8/install-elasticsearch.html).

   > NOTE: <br>
   From this point forward, the environment variable `$ES_HOME` will be used to refer to the location where Elasticsearch is installed. You can set this environment variable yourself, or manually substitute the appropriate value for it in subsequent commands.
   <br>
   For example, `export ES_HOME="~/VNet-Flow-Logs-Visualization/elasticsearch-8.8.1"`

3. Verify that Elasticsearch is running with the command:

   ```bash
   curl --cacert $ES_HOME/config/certs/http_ca.crt -u elastic https://localhost:9200
   ```

    You'll be prompted for the password for the 'elastic' user. On entering the password, you should see a response similar to this:

   ```json
   {
     "name" : "DESKTOP-4AORLVL",
     "cluster_name" : "elasticsearch",
     "cluster_uuid" : "3pBvU1X8TdyFb-jdzzhjvA",
     "version" : {
       "number" : "8.8.1",
       "build_flavor" : "default",
       "build_type" : "tar",
       "build_hash" : "f8edfccba429b6477927a7c1ce1bc6729521305e",
       "build_date" : "2023-06-05T21:32:25.188464208Z",
       "build_snapshot" : false,
       "lucene_version" : "9.6.0",
       "minimum_wire_compatibility_version" : "7.17.0",
       "minimum_index_compatibility_version" : "7.0.0"
     },
     "tagline" : "You Know, for Search"
   }
   ```

For further instructions on installing Elastic search from the Linux archive, refer to [Installation instructions](https://www.elastic.co/guide/en/elasticsearch/reference/8.8/targz.html).

### Install Logstash

1. To install Logstash using apt, run the following [commands](https://www.elastic.co/guide/en/logstash/8.8/installing-logstash.html#_apt):

    ```bash
   wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elastic-keyring.gpg
   sudo apt-get install apt-transport-https
   echo "deb [signed-by=/usr/share/keyrings/elastic-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee -a /etc/apt/sources.list.d/elastic-8.x.list
   sudo apt-get update && sudo apt-get install logstash
    ```

2. Create a user for Logstash to connect to Elasticsearch:
   
   1. Create a role for Logstash to write to Elasticsearch.
      ```bash
      curl --cacert $ES_HOME/config/certs/http_ca.crt -u elastic -X POST "https://localhost:9200/_security/role/logstash_writer?pretty" -H 'Content-Type: application/json' -d'
      {
        "cluster": ["manage_index_templates", "monitor", "manage_ilm"], 
        "indices": [
          {
            "names": [ "vnet-flow-logs", "nsg-flow-logs" ], 
            "privileges": ["write","create","create_index","manage","manage_ilm"]  
          }
        ]
      }
      '
      ```
   
   2. Create the Logstash user using the role created above.
      ```bash
      curl --cacert $ES_HOME/config/certs/http_ca.crt -u elastic -X POST "https://localhost:9200/_security/user/logstash_internal?pretty" -H 'Content-Type: application/json' -d'
      {
        "password" : "logstash-password",
        "roles" : [ "logstash_writer" ],
        "full_name" : "Internal Logstash User"
      }
      '
      ```      

3. Next we need to configure Logstash to access and parse the flow logs. Create a logstash.conf file using:

    ```bash
    sudo touch /etc/logstash/conf.d/logstash.conf
    ```

4. Add the following content to the file:

   ```
   input {
      azure_blob_storage
       {
           storageaccount => "flowst"
           access_key => "g9aFKL81HpHQ5ObQ5AbU7nBSHwn971WJdVlrCo+ik4Ms5DwsuInxEqgy37StYsKzzFB+RHghOyie+AStgY6xdQ=="
           container => "insights-logs-flowlogflowevent"
           codec => "json"
           # Refer https://learn.microsoft.com/azure/network-watcher/vnet-flow-logs-read
       }
   }

   filter {
       split { field => "[records]" }
       split { field => "[records][flowRecords][flows]"}
       split { field => "[records][flowRecords][flows][flowGroups]"}
       split { field => "[records][flowRecords][flows][flowGroups][flowTuples]"}

       mutate{
           split => { "[records][targetResourceID]" => "/"}
           add_field => {
                        "Subscription" => "%{[records][targetResourceID][2]}"
                        "ResourceGroup" => "%{[records][targetResourceID][4]}"
                        "VirtualNetwork" => "%{[records][targetResourceID][8]}"
                     }
           convert => {"Subscription" => "string"}
           convert => {"ResourceGroup" => "string"}
           convert => {"VirtualNetwork" => "string"}
           split => { "[records][flowRecords][flows][flowGroups][flowTuples]" => ","}
           add_field => {
                        "unixtimestamp" => "%{[records][flowRecords][flows][flowGroups][flowTuples][0]}"
                        "srcIp" => "%{[records][flowRecords][flows][flowGroups][flowTuples][1]}"
                        "destIp" => "%{[records][flowRecords][flows][flowGroups][flowTuples][2]}"
                        "srcPort" => "%{[records][flowRecords][flows][flowGroups][flowTuples][3]}"
                        "destPort" => "%{[records][flowRecords][flows][flowGroups][flowTuples][4]}"

                        "protocol" => "%{[records][flowRecords][flows][flowGroups][flowTuples][5]}"
                        "trafficflow" => "%{[records][flowRecords][flows][flowGroups][flowTuples][6]}"

                        "traffic" => "%{[records][flowRecords][flows][flowGroups][flowTuples][7]}"
                        "flowstate" => "%{[records][flowRecords][flows][flowGroups][flowTuples][8]}"

                        "packetsSourceToDest" => "%{[records][flowRecords][flows][flowGroups][flowTuples][9]}"
                        "bytesSentSourceToDest" => "%{[records][flowRecords][flows][flowGroups][flowTuples][10]}"
                        "packetsDestToSource" => "%{[records][flowRecords][flows][flowGroups][flowTuples][11]}"
                        "bytesSentDestToSource" => "%{[records][flowRecords][flows][flowGroups][flowTuples][12]}"
                     }
           convert => {"unixtimestamp" => "integer"}
           convert => {"srcPort" => "integer"}
           convert => {"destPort" => "integer"}        
       }

       date{
           match => ["unixtimestamp" , "UNIX"]
       }
    }
   output {
       stdout { codec => rubydebug }
       elasticsearch {
           hosts => "https://localhost"

           # SSL enabled 
           ssl => true 
           ssl_certificate_verification => true 
           
           # Path to your Cluster Certificate .pem downloaded earlier 
           cacert => "<path-to-ESHOME>/config/certs/http_ca.crt" 

           index => "vnet-flow-logs"
           user => "logstash_internal"
           password => "logstash-password"
       }
   }
   ```

For further instructions on installing Logstash, refer to the [official documentation](https://www.elastic.co/guide/en/logstash/8.8/installing-logstash.html).

### Install the Logstash input plugin for Azure blob storage

This open-source Logstash plugin ([azure_blob_storage](https://github.com/janmg/logstash-input-azure_blob_storage/tree/master)) will allow you to directly access the flow logs from their designated storage account. To install this plugin, from the default Logstash installation directory (in this case /usr/share/logstash/bin) run the command:

```bash
sudo /usr/share/logstash/bin/logstash-plugin install logstash-input-azure_blob_storage
```

To start Logstash run the command:

```bash
sudo systemctl start logstash
```

For more information about this plugin, refer to the [documentation](https://github.com/janmg/logstash-input-azure_blob_storage/tree/master).

### Install Grafana

To install and run Grafana, run the following commands:

```bash
sudo apt-get install -y apt-transport-https
sudo apt-get install -y software-properties-common wget
sudo wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key
echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list
sudo apt-get update
# Installs the latest OSS release:
sudo apt-get install grafana
sudo systemctl start grafana-server
```

For additional installation information, see [Install Grafana on Debian or Ubuntu](https://grafana.com/docs/grafana/latest/setup-grafana/installation/debian/).

#### Accessing the Grafana server

You can access your Grafana server at `http://localhost:3000`

The default credentials to log into Grafana v10.0 are to set both username and password to "admin". You'll be prompted to change the password once you log in.

![Grafana Server Login][grafana-login]

#### Add the ElasticSearch server as a data source

Next, you need to add the ElasticSearch index containing flow logs as a data source. You can add a data source by selecting **Home > Connections > Data sources > Add data source**, selecting **Elasticsearch** from the list of data source types, and completing the form with the relevant information. A sample of this configuration can be found in the following screenshot:

![Add data source][grafana-data-source]

- Select the `Basic auth` option, and specify the credentials for your `elastic` user in the Basic Auth Details section. 
- Select the `With CA Cert` option, and paste the contents of `$ESHOME/config/certs/http_ca.crt` into the text-box for the CA Cert under the TLS/SSL Auth Details section.
- Under the Elasticsearch details section, set the `Index name` to "vnet-flow-logs" (or whichever index name you've used in your Logstash config).
- Select the `X-Pack enabled` option.

#### Create a dashboard

Now that you have successfully configured Grafana to read from the ElasticSearch index containing VNet flow logs, you can create and personalize dashboards. To create a new dashboard, select **Create your first dashboard**. The following sample graph configuration shows flows segmented by NSG rule:

![Dashboard graph][grafana-dashboard]

Grafana is highly customizable so it's advisable that you create dashboards to suit your specific monitoring needs. The following example depicts a dashboard describing network traffic across numerous resources in a subscription using [Traffic Analytics](traffic-analytics.md):

![Screenshot that shows the sample graph configuration with flows segmented by NSG rule.][sample-flow-logs-dashboard]

## Conclusion

By integrating Network Watcher with ElasticSearch and Grafana, you now have a convenient and centralized way to manage and visualize VNet flow logs as well as other data. Grafana has a number of other powerful graphing features that can also be used to further manage flow logs and better understand your network traffic. Now that you have a Grafana instance set up and connected to Azure, feel free to continue to explore the other functionality that it offers.

## Next steps

- Learn more about using [Network Watcher](network-watcher-monitoring-overview.md).

<!--Image references-->

[1]: ./media/vnet-flow-logs-analyze-grafana/grafana-fig1.png
[grafana-login]: ./media/vnet-flow-logs-analyze-grafana/grafana-login.png
[grafana-data-source]: ./media/vnet-flow-logs-analyze-grafana/grafana-data-source.png
[grafana-dashboard]: ./media/vnet-flow-logs-analyze-grafana/grafana-dashboard.png
[sample-flow-logs-dashboard]: ./media/vnet-flow-logs-analyze-grafana/grafana-vnet-flow-logs-sample-dashboard.png




━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Elasticsearch security features have been automatically configured!
✅ Authentication is enabled and cluster connections are encrypted.

ℹ️  Password for the elastic user (reset with `bin/elasticsearch-reset-password -u elastic`):
  Q2*uw43f*iufd1nE*yto

ℹ️  HTTP CA certificate SHA-256 fingerprint:
  d596301f8c4079b8c56f32bfe6a7bff8905fdeba802c2aef62957f84b200b9df

ℹ️  Configure Kibana to use this cluster:
• Run Kibana and click the configuration link in the terminal when Kibana starts.
• Copy the following enrollment token and paste it into Kibana in your browser (valid for the next 30 minutes):
  eyJ2ZXIiOiI4LjguMiIsImFkciI6WyIxMC4wLjAuNDo5MjAwIl0sImZnciI6ImQ1OTYzMDFmOGM0MDc5YjhjNTZmMzJiZmU2YTdiZmY4OTA1ZmRlYmE4MDJjMmFlZjYyOTU3Zjg0YjIwMGI5ZGYiLCJrZXkiOiJwa2h4UVk0QkZ2d19oUmo1eGJrRDpkaGhGU2h4UVJnT1c2VTNfQVBzM0dRIn0=

ℹ️  Configure other nodes to join this cluster:
• On this node:
  ⁃ Create an enrollment token with `bin/elasticsearch-create-enrollment-token -s node`.
  ⁃ Uncomment the transport.host setting at the end of config/elasticsearch.yml.
  ⁃ Restart Elasticsearch.
• On other nodes:
  ⁃ Start Elasticsearch with `bin/elasticsearch --enrollment-token <token>`, using the enrollment token that you generated.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━