# 0.1.4
* set method signature fix 
* ttl will respect key zipping

# 0.1.3
* minor messaging changes for AWS config, warning popups not on config calls 
but on prepend. Config calls just displays resulting config now

# 0.1.2
* add AwsConfigBlocker extension. Prepending MeRedis successor with this module 
prevents error while using the MeRedis with AWS ElasticCache (AWS blocks all config calls).

* added docker-compose for local testing comfort 

* awesome_print prod dependency 
 
# 0.1.1
* add MockRedis extension 