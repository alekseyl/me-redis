require 'ap'
module MeRedis
  # how to use:
  # Redis.include( MeRedis::AwsConfigBlocker )
  module AwsConfigBlocker

     def config( *args, &block )
      print <<AWS_MSG
     
      \e[0;33;31;1m!!!!!!!!! MeRedis AWS CONFIG BLOCKER WARNING!!!!!! \e[0;33;31;0m
      You introduced AwsConfigBlocker into the ancestors chain, that means that you intend to skip Redis config call,
      because AWS does not support config get/set calls by throwing an exception. 
      AwsConfigBlocker will block config call from reaching your Redis server!

      You are calling config with arguments:

AWS_MSG

       ap args

       print <<END_MSG
       

       Don't forget to setup redis param group with exact values, or you might face unexpected optimization degradation. 
       You can find more details in the README section.
END_MSG
       {}
    end
  end
end