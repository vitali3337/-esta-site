#!/bin/bash
set -e

DOMAIN="esta.md"
EMAIL="info@esta.md"

RED='\033[0;31m'
GREEN='\033[0;32m'
GOLD='\033[0;33m'
NC='\033[0m'

echo ""
echo -e "${GOLD}╔═══════════════════════════════════╗${NC}"
echo -e "${GOLD}║   ESTA · Deploy Script v1.0       ║${NC}"
echo -e "${GOLD}║   Молдова & Приднестровье          ║${NC}"
echo -e "${GOLD}╚═══════════════════════════════════╝${NC}"
echo ""

if [ ! -f ".env" ]; then
  echo -e "${RED}✗ Файл .env не найден!${NC}"
  exit 1
fi

if grep -q "ВАШ_ТОКЕН\|your_telegram\|your_anthropic" .env; then
  echo -e "${RED}✗ В .env остались незаполненные значения!${NC}"
  exit 1
fi

echo -e "${GREEN}✓ .env проверен${NC}"

if ! command -v docker &> /dev/null; then
  echo "Устанавливаю Docker..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker
  systemctl start docker
  echo -e "${GREEN}✓ Docker установлен${NC}"
else
  echo -e "${GREEN}✓ Docker уже установлен${NC}"
fi

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
  echo "Устанавливаю Docker Compose..."
  apt-get install -y docker-compose-plugin 2>/dev/null || \
  curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose
  echo -e "${GREEN}✓ Docker Compose установлен${NC}"
else
  echo -e "${GREEN}✓ Docker Compose уже установлен${NC}"
fi

if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
  echo "Получаю SSL-сертификат для $DOMAIN..."
  apt-get install -y certbot 2>/dev/null || true
  docker run --rm -p 80:80 \
    -v /etc/letsencrypt:/etc/letsencrypt \
    certbot/certbot certonly \
    --standalone \
    --email $EMAIL \
    --agree-tos \
    --no-eff-email \
    -d $DOMAIN -d www.$DOMAIN
  echo -e "${GREEN}✓ SSL-сертификат получен${NC}"
else
  echo -e "${GREEN}✓ SSL уже настроен${NC}"
fi

echo ""
echo "Собираю контейнеры..."
docker compose build --no-cache

echo ""
echo "Запускаю ESTA..."
docker compose up -d

sleep 5
echo ""
echo "Статус контейнеров:"
docker compose ps

CRON_JOB="0 3 * * * docker run --rm -v /etc/letsencrypt:/etc/letsencrypt certbot/certbot renew --quiet && docker compose restart nginx"
(crontab -l 2>/dev/null | grep -v certbot; echo "$CRON_JOB") | crontab -
echo -e "${GREEN}✓ Автообновление SSL настроено${NC}"

echo ""
echo -e "${GOLD}═══════════════════════════════════════${NC}"
echo -e "${GREEN}  🚀 ESTA успешно запущен!${NC}"
echo -e "${GOLD}═══════════════════════════════════════${NC}"
echo ""
echo -e "  🌐 Лендинг:    ${GREEN}https://$DOMAIN${NC}"
echo -e "  🤖 Telegram:   ${GREEN}https://t.me/esta_realty_bot${NC}"
echo ""
echo -e "  Логи бота:     ${GOLD}docker logs -f esta_bot${NC}"
echo -e "  Логи парсера:  ${GOLD}docker logs -f esta_parser${NC}"
echo -e "  Перезапуск:    ${GOLD}docker compose restart${NC}"
echo -e "  Остановка:     ${GOLD}docker compose down${NC}"
echo ""
