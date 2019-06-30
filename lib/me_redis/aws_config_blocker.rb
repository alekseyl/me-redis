require 'ap'
module MeRedis
  # how to use:
  # Redis.include( MeRedis::AwsConfigBlocker )
  module AwsConfigBlocker

     def config( *args, &block )
       print 'config was called, resulting me_config:'
       ap self.class.me_config
       {}
     end

     def self.prepended(base)
       print <<AWS_MSG
        
        \e[0;33;31;1m!!!!!!!!! MeRedis AWS CONFIG BLOCKER WARNING!!!!!! \e[0;33;31;0m
        You introduced AwsConfigBlocker into the ancestors chain, that means that you intend to skip Redis config call,
        because AWS does not support config get/set calls by throwing an exception. 
        AwsConfigBlocker will block config call from reaching your Redis server!
        
        Don't forget to setup redis param group through the AWS UI with exact values, or you might face unexpected 
        optimization degradation. For more details look into the README section.

AWS_MSG
     end
   end
end