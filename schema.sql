CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

CREATE TABLE cities (
  id        SERIAL PRIMARY KEY,
  name_ru   VARCHAR(100) NOT NULL,
  name_ro   VARCHAR(100),
  region    VARCHAR(50) CHECK (region IN ('moldova', 'transnistria')),
  slug      VARCHAR(100) UNIQUE NOT NULL
);

INSERT INTO cities (name_ru, name_ro, region, slug) VALUES
  ('Кишинёв',   'Chișinău',  'moldova',      'chisinau'),
  ('Бельцы',    'Bălți',     'moldova',      'balti'),
  ('Тирасполь', 'Tiraspol',  'transnistria', 'tiraspol'),
  ('Бендеры',   'Bender',    'transnistria', 'bendery'),
  ('Рыбница',   'Râbnița',   'transnistria', 'rybnitsa'),
  ('Дубоссары', 'Dubăsari',  'transnistria', 'dubossary');

CREATE TABLE properties (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  external_id     VARCHAR(255) UNIQUE,
  source          VARCHAR(50) DEFAULT 'manual',
  deal_type       VARCHAR(20) NOT NULL CHECK (deal_type IN ('sale', 'rent')),
  property_type   VARCHAR(50) NOT NULL CHECK (property_type IN (
                    'apartment', 'house', 'commercial', 'garage', 'storage', 'land'
                  )),
  is_new_build    BOOLEAN DEFAULT FALSE,
  city_id         INTEGER REFERENCES cities(id),
  district        VARCHAR(200),
  address         VARCHAR(500),
  lat             DECIMAL(10,7),
  lng             DECIMAL(10,7),
  rooms           SMALLINT CHECK (rooms BETWEEN 0 AND 20),
  floor           SMALLINT,
  floors_total    SMALLINT,
  area_total      DECIMAL(8,2),
  area_living     DECIMAL(8,2),
  area_kitchen    DECIMAL(8,2),
  price           DECIMAL(14,2) NOT NULL,
  currency        VARCHAR(5) DEFAULT 'USD' CHECK (currency IN ('USD','EUR','MDL','RUB')),
  price_usd       DECIMAL(14,2),
  price_per_sqm   DECIMAL(10,2),
  title           VARCHAR(500),
  description     TEXT,
  description_ai  TEXT,
  photos          TEXT[],
  video_url       VARCHAR(500),
  contact_name    VARCHAR(200),
  contact_phone   VARCHAR(50),
  contact_type    VARCHAR(20) DEFAULT 'owner' CHECK (contact_type IN ('owner','agent','developer')),
  is_active       BOOLEAN DEFAULT TRUE,
  is_featured     BOOLEAN DEFAULT FALSE,
  views_count     INTEGER DEFAULT 0,
  source_url      VARCHAR(500),
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW(),
  published_at    TIMESTAMPTZ DEFAULT NOW(),
  expires_at      TIMESTAMPTZ
);

CREATE INDEX idx_properties_city        ON properties(city_id);
CREATE INDEX idx_properties_deal_type   ON properties(deal_type);
CREATE INDEX idx_properties_prop_type   ON properties(property_type);
CREATE INDEX idx_properties_price_usd   ON properties(price_usd);
CREATE INDEX idx_properties_rooms       ON properties(rooms);
CREATE INDEX idx_properties_active      ON properties(is_active);
CREATE INDEX idx_properties_created     ON properties(created_at DESC);
CREATE INDEX idx_properties_external    ON properties(external_id);
CREATE INDEX idx_properties_source      ON properties(source);

CREATE INDEX idx_properties_fts ON properties
  USING GIN (to_tsvector('russian', COALESCE(title,'') || ' ' || COALESCE(description,'')));

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_properties_updated
  BEFORE UPDATE ON properties
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE OR REPLACE FUNCTION calc_price_per_sqm()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.area_total > 0 AND NEW.price_usd IS NOT NULL THEN
    NEW.price_per_sqm := ROUND(NEW.price_usd / NEW.area_total, 2);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_price_per_sqm
  BEFORE INSERT OR UPDATE ON properties
  FOR EACH ROW EXECUTE FUNCTION calc_price_per_sqm();

CREATE TABLE leads (
  id              SERIAL PRIMARY KEY,
  property_id     UUID REFERENCES properties(id) ON DELETE SET NULL,
  telegram_id     BIGINT,
  name            VARCHAR(200),
  phone           VARCHAR(50),
  message         TEXT,
  intent          VARCHAR(20) CHECK (intent IN ('buy','rent','sell','partner')),
  status          VARCHAR(20) DEFAULT 'new' CHECK (status IN ('new','contacted','closed')),
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE agents (
  id              SERIAL PRIMARY KEY,
  name            VARCHAR(200) NOT NULL,
  phone           VARCHAR(50),
  email           VARCHAR(200),
  agency          VARCHAR(200),
  plan            VARCHAR(20) DEFAULT 'free' CHECK (plan IN ('free','agency','developer')),
  telegram_id     BIGINT,
  is_active       BOOLEAN DEFAULT TRUE,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE properties ADD COLUMN agent_id INTEGER REFERENCES agents(id);

CREATE VIEW v_stats AS
SELECT
  COUNT(*) FILTER (WHERE is_active)                           AS total_active,
  COUNT(*) FILTER (WHERE deal_type='sale' AND is_active)      AS for_sale,
  COUNT(*) FILTER (WHERE deal_type='rent' AND is_active)      AS for_rent,
  COUNT(*) FILTER (WHERE is_new_build AND is_active)          AS new_builds,
  COUNT(*) FILTER (WHERE source='manual')                     AS manual_entries,
  COUNT(*) FILTER (WHERE source IN ('makler','999md'))        AS parsed_entries,
  ROUND(AVG(price_usd) FILTER (WHERE is_active AND deal_type='sale'), 0) AS avg_sale_price_usd,
  MAX(created_at)                                             AS last_added
FROM properties;
