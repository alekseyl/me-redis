FROM ruby:2.7

WORKDIR me-redis

ADD . /me-redis/
RUN gem install bundler
RUN bundle install