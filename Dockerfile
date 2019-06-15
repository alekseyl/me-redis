FROM ruby:2.5

WORKDIR me-redis

ADD . /me-redis/
RUN bundle install