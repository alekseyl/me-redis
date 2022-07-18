FROM ruby:3-bullseye

WORKDIR me-redis

ADD . /me-redis/
RUN gem install bundler
RUN bundle install