# WordPress site @DOMAIN@ — rebuilt 2026-11-13. Own php-fpm pool (wp-@SITE@), no PHP in uploads, dotfiles/dumps denied.
server {
    listen 80;
    listen [::]:80;
    server_name @DOMAIN@;
    return 301 https://@DOMAIN@$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name @DOMAIN@;

    ssl_certificate /etc/letsencrypt/live/@DOMAIN@/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/@DOMAIN@/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    root @ROOT@;
    index index.php;

    access_log /var/log/nginx/@SITE@.access.log;
    error_log  /var/log/nginx/@SITE@.error.log;

    client_max_body_size 64m;

    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;


    # Never serve: dotfiles, dumps and archives, logs, backup copies, config and docs.
    location ~ /\.(?!well-known) { deny all; }
    location ~* \.(sql|sql\.gz|gz|zip|tar|tgz|bak|old|orig|swp|log|ini|conf|env|sh|git)$ { deny all; }
    location ~* ^/(wp-config\.php|wp-config-sample\.php|readme\.html|license\.txt)$ { deny all; }
    location = /xmlrpc.php { deny all; }

    # PHP never runs from uploads (or any other user-writable place).
    location ~* ^/wp-content/uploads/.*\.(php[0-9]?|phtml|phar|pht|pl|py|cgi|asp|aspx|jsp)$ { deny all; }

    location = /wp-login.php {
        limit_req zone=wplogin burst=8 nodelay;
        limit_req_status 429;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        fastcgi_pass unix:/run/php/php8.4-fpm-wp-@SITE@.sock;
    }

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        try_files $uri =404;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT $realpath_root;
        fastcgi_pass unix:/run/php/php8.4-fpm-wp-@SITE@.sock;
        fastcgi_read_timeout 60s;
    }

    location ~* \.(?:css|js|woff2?|ttf|svg|ico|png|jpe?g|gif|webp|avif)$ {
        expires 30d;
        access_log off;
        try_files $uri =404;
    }

    location = /favicon.ico { log_not_found off; access_log off; }
    location = /robots.txt  { log_not_found off; access_log off; }
}
