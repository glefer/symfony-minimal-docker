# syntax=docker/dockerfile:1.4
ARG PHP_IMAGE=8.1.7
ARG COMPOSER_VERSION=2.3.7
FROM composer:${COMPOSER_VERSION} as composer

FROM php:${PHP_IMAGE}-fpm-alpine3.16 as builder
ARG PHP_IMAGE

MAINTAINER Gregory LEFER <12687145+glefer@users.noreply.github.com>
WORKDIR /app

# Install needed dependancies
RUN apk add --no-cache git
COPY --from=composer /usr/bin/composer /usr/bin/composer

COPY --link conf/php/common/preload.php /var/www/

RUN apk add --no-cache --virtual .build-deps libzip-dev icu-dev $PHPIZE_DEPS  \
    && apk add --no-cache curl icu-libs libintl libzip \
    && pecl install apcu \
    && docker-php-ext-configure intl  \
    && docker-php-ext-install opcache intl pdo_mysql zip intl exif \
    && docker-php-ext-enable apcu intl \
    && pecl clear-cache \
    && apk del .build-deps \
    && rm -rf /tmp/*

COPY --link conf/php/common/symfony.ini /usr/local/etc/php/conf.d/symfony.ini

FROM builder as prod
ENV APP_ENV prod
RUN  sed -i 's/opcache.validate_timestamps.*/opcache.validate_timestamps=0/' /usr/local/etc/php/conf.d/symfony.ini

## Dev application
FROM builder as dev

RUN apk add --no-cache --virtual .build-deps  $PHPIZE_DEPS  \
    && apk add --no-cache git \
    && pecl install pcov \
    && docker-php-ext-enable pcov \
    && pecl clear-cache \
    && apk del .build-deps \
    && rm -rf /tmp/*

RUN version=$(php -r "echo PHP_MAJOR_VERSION.PHP_MINOR_VERSION;") \
    && architecture=$(uname -m) \
    && curl -A "Docker" -o /tmp/blackfire-probe.tar.gz -D - -L -s https://blackfire.io/api/v1/releases/probe/php/alpine/$architecture/$version \
    && mkdir -p /tmp/blackfire \
    && tar zxpf /tmp/blackfire-probe.tar.gz -C /tmp/blackfire \
    && mv /tmp/blackfire/blackfire-*.so $(php -r "echo ini_get ('extension_dir');")/blackfire.so \
    && printf "extension=blackfire.so\nblackfire.agent_socket=tcp://blackfire:8307\n" > $PHP_INI_DIR/conf.d/blackfire.ini \
    && rm -rf /tmp/blackfire /tmp/blackfire-probe.tar.gz