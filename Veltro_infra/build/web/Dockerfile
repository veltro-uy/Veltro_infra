FROM php:8.4-apache

ENV DEBIAN_FRONTEND=noninteractive

# Instalar dependencias
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libzip-dev \
        libpng-dev \
        libonig-dev \
        libjpeg-dev \
        libfreetype6-dev \
        git \
        unzip \
        curl \
        vim \
        nano && \
    rm -rf /var/lib/apt/lists/*

# Instalar extensiones PHP
RUN docker-php-ext-configure gd --with-freetype --with-jpeg && \
    docker-php-ext-install \
        pdo \
        pdo_mysql \
        mysqli \
        mbstring \
        zip \
        gd \
        exif \
        pcntl \
        bcmath

# Habilitar módulos Apache
RUN a2enmod rewrite ssl headers deflate expires

# Instalar Composer
RUN curl -sS https://getcomposer.org/installer | php -- \
    --install-dir=/usr/local/bin \
    --filename=composer

# Configurar PHP
RUN echo "memory_limit = 512M" >> /usr/local/etc/php/conf.d/custom.ini && \
    echo "upload_max_filesize = 64M" >> /usr/local/etc/php/conf.d/custom.ini && \
    echo "post_max_size = 64M" >> /usr/local/etc/php/conf.d/custom.ini && \
    echo "max_execution_time = 300" >> /usr/local/etc/php/conf.d/custom.ini

# Configurar permisos
RUN chown -R www-data:www-data /var/www/html && \
    chmod -R 755 /var/www/html

EXPOSE 80 443

CMD ["apache2-foreground"]